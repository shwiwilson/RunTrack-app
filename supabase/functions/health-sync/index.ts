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
  syncConnection,
} from "../_shared/health_runtime.ts";
Deno.serve(handled(async (request) => {
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
  const connections = check(
    await query.order("last_successful_sync_at", {
      ascending: true,
      nullsFirst: true,
    }).limit(1),
  ) ?? [];
  if (!connections.length && user) {
    throw new HttpError(409, "Connect Google Health before syncing workouts.");
  }
  let imported = 0, failed = 0, partial = false;
  for (const connection of connections) {
    try {
      const cursor = connection.sync_cursor as Record<string, unknown>;
      const pending = check(
        await client.from("sync_events").select("id").eq(
          "connection_id",
          connection.id,
        ).is("processed_at", null).limit(1),
      ) ?? [];
      const full = pending.length > 0 || !cursor.last_full_sync ||
        Date.parse(String(cursor.last_full_sync)) < Date.now() - 86400000;
      const result = await syncConnection(client, connection, full);
      imported += result.imported;
      partial ||= !result.complete;
    } catch (error) {
      failed++;
      if (error instanceof HttpError && error.status === 403) {
        if (user) throw error;
        continue;
      }
      if (error instanceof HttpError && error.status === 401) {
        check(
          await client.rpc("withdraw_health_consent", {
            p_user_id: connection.user_id,
            p_reason: "provider_revoked",
          }),
        );
        continue;
      }
      check(
        await client.from("health_connections").update({
          status: "error",
          last_error: error instanceof HttpError
            ? error.message
            : "Workout sync could not finish. Please retry.",
        }).eq("id", connection.id).in("status", ["connected", "error"]),
      );
    }
  }
  return json(request, {
    status: failed ? "error" : partial ? "partial" : "synced",
    imported,
    failed,
  }, failed && user ? 502 : 200);
}));
