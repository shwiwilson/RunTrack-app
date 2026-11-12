import {
  check,
  handled,
  HttpError,
  json,
  requireUser,
  serviceClient,
} from "../_shared/health_runtime.ts";

Deno.serve(handled(async (request) => {
  if (request.method !== "POST") throw new HttpError(405, "Use POST.");
  const service = serviceClient();
  const user = await requireUser(request, service);
  const output: Record<string, unknown> = {
    format_version: 1,
    exported_at: new Date().toISOString(),
    identity: { id: user.id, email: user.email, created_at: user.created_at },
  };
  // Paginate so a long training history is never silently truncated to the
  // PostgREST default row limit. Every privileged query is scoped to this user.
  for (
    const table of [
      "profiles",
      "club_memberships",
      "activities",
      "challenge_participants",
      "session_rsvps",
      "race_results",
      "health_connections",
      "health_data_consents",
    ]
  ) {
    const rows: unknown[] = [];
    for (let offset = 0;; offset += 1000) {
      const page = check(
        await service.from(table).select("*")
          .eq(table === "profiles" ? "id" : "user_id", user.id)
          .order("id").range(offset, offset + 999),
      ) ?? [];
      rows.push(...page);
      if (page.length < 1000) break;
    }
    output[table] = rows;
  }
  const laps: unknown[] = [];
  for (let offset = 0;; offset += 1000) {
    const page = check(
      await service.from("activity_laps")
        .select("*,activities!inner(user_id)").eq("activities.user_id", user.id)
        .order("id").range(offset, offset + 999),
    ) ?? [];
    laps.push(...page.map(({ activities: _owner, ...lap }) => lap));
    if (page.length < 1000) break;
  }
  output.activity_laps = laps;
  const connectionIds = (output.health_connections as { id: string }[]).map(
    (row) => row.id,
  );
  const jobs: unknown[] = [];
  if (connectionIds.length) {
    for (let offset = 0;; offset += 1000) {
      const page = check(
        await service.from("sync_jobs").select("*")
          .in("connection_id", connectionIds).order("id").range(
            offset,
            offset + 999,
          ),
      ) ?? [];
      jobs.push(...page);
      if (page.length < 1000) break;
    }
  }
  output.sync_jobs = jobs;
  output.calculations =
    "Personal bests, achievements and leaderboards are derived from stored activities and confirmed attendance; no separate athlete data is generated.";
  // Provider credentials, passwords, access tokens and other runners' records
  // are deliberately outside the export contract.
  return json(request, output);
}));
