import { constantTimeEqual } from "../_shared/health_core.ts";
import {
  check,
  configurationRequired,
  env,
  handled,
  HttpError,
  json,
  requireUser,
  serviceClient,
  SyncAlreadyRunning,
  syncConnection,
} from "../_shared/health_runtime.ts";
import {
  HealthSyncBudget,
  runHealthBatch,
} from "../_shared/health_sync_budget.ts";
Deno.serve(handled(async (request) => {
  const invocationDeadline = Date.now() + 90000;
  if (request.method !== "POST") throw new HttpError(405, "Use POST.");
  const client = serviceClient();
  const secret = env("HEALTH_RECONCILE_SECRET");
  const scheduled = !!secret &&
    constantTimeEqual(
      request.headers.get("authorization") ?? "",
      `Bearer ${secret}`,
    );
  const user = scheduled ? null : await requireUser(request, client);
  if (configurationRequired().length) {
    return json(request, {
      status: "setup_required",
      message: "Google Health is awaiting secure deployment configuration.",
    });
  }
  let query = client.from("health_connections").select("*").eq(
    "provider",
    "google_health",
  ).in("status", ["connected", "error"]);
  if (user) query = query.eq("user_id", user.id);
  const invocationBudget = new HealthSyncBudget(invocationDeadline);
  const connections = check(
    // Scheduled failures and partial imports must move behind other athletes;
    // sorting by success alone lets a few broken connections starve the club.
    await invocationBudget.database(
      query.order(scheduled ? "updated_at" : "last_successful_sync_at", {
        ascending: true,
        nullsFirst: true,
      }).limit(scheduled ? 5 : 1),
    ),
  ) ?? [];
  if (!connections.length && user) {
    throw new HttpError(409, "Connect Google Health before syncing workouts.");
  }
  let imported = 0, failed = 0, partial = false;
  const processConnection = async (connection: Record<string, unknown>) => {
    const budget = new HealthSyncBudget(
      Math.min(
        invocationDeadline - 5000,
        Date.now() + (scheduled ? 25000 : 90000),
      ),
    );
    const touch = () =>
      invocationBudget.database(
        client.from("health_connections").update({
          updated_at: new Date().toISOString(),
        }).eq("id", connection.id),
      );
    try {
      const cursor = (connection.sync_cursor ?? {}) as Record<string, unknown>;
      if (Date.parse(String(cursor.retry_at)) > Date.now()) {
        partial = true;
        check(await touch());
        return;
      }
      const pending = check(
        await budget.database(
          client.from("sync_events").select("id").eq(
            "connection_id",
            connection.id,
          ).is("processed_at", null).limit(1),
        ),
      ) ?? [];
      const full = pending.length > 0 || !cursor.last_full_sync ||
        Date.parse(String(cursor.last_full_sync)) < Date.now() - 86400000;
      const result = await syncConnection(
        client,
        connection,
        full,
        undefined,
        budget,
      );
      imported += result.imported;
      partial ||= !result.complete;
    } catch (error) {
      if (error instanceof SyncAlreadyRunning) {
        partial = true;
        check(await touch());
        return;
      }
      if (error instanceof HttpError && error.status === 403) {
        if (user) throw error;
        // A newer grant may have arrived after the failing check. Do not withdraw it.
        partial = true;
        check(await touch());
        return;
      }
      if (error instanceof HttpError && error.status === 401) {
        check(
          await invocationBudget.database(
            client.rpc("withdraw_health_consent", {
              p_user_id: connection.user_id,
              p_reason: "provider_revoked",
            }),
          ),
        );
        failed++;
        return;
      }
      check(
        await invocationBudget.database(
          client.from("health_connections").update({
            status: "error",
            last_error: error instanceof HttpError
              ? error.message
              : "Workout sync could not finish. Please retry.",
          }).eq("id", connection.id).in("status", ["connected", "error"]),
        ),
      );
      failed++;
    }
  };
  // Keep provider work bounded and isolate one athlete's failure from the next.
  // A user-triggered request still handles only the initiating athlete.
  const batch = await runHealthBatch(connections, processConnection, {
    concurrency: scheduled ? 2 : 1,
    startBefore: invocationDeadline - 15000,
  });
  if (user && batch.failures[0] instanceof HttpError) throw batch.failures[0];
  failed += batch.failures.length;
  partial ||= batch.deferred > 0;
  return json(request, {
    status: failed ? "error" : partial ? "partial" : "synced",
    imported,
    failed,
  }, failed && user ? 502 : 200);
}));
