import { decrypt } from "../_shared/health_core.ts";
import {
  check,
  env,
  handled,
  HttpError,
  json,
  requireUser,
  serviceClient,
} from "../_shared/health_runtime.ts";
Deno.serve(handled(async (request) => {
  if (request.method !== "POST") throw new HttpError(405, "Use POST.");
  const client = serviceClient(), user = await requireUser(request, client);
  const connection = check(
    await client.from("health_connections").select("id").eq("user_id", user.id)
      .eq("provider", "google_health").maybeSingle(),
  );
  if (connection) {
    const jobId = check(
      await client.rpc("claim_health_sync", { p_connection_id: connection.id }),
    );
    if (!jobId) {
      throw new HttpError(
        409,
        "A sync is running. Wait a moment before disconnecting.",
      );
    }
    try {
      const credentials = check(
        await client.rpc("health_credentials_get", {
          p_connection_id: connection.id,
        }),
      );
      const token = credentials
        ? await decrypt(
          credentials.refresh_token_ciphertext,
          env("HEALTH_TOKEN_ENCRYPTION_KEY"),
          connection.id,
        )
        : null;
      // Stop local access first; even a failed remote revocation cannot reactivate syncing.
      check(
        await client.from("health_connections").update({
          status: "disconnected",
          provider_user_id: null,
          last_error: null,
          sync_cursor: {},
        }).eq("id", connection.id),
      );
      check(await client.from("oauth_states").delete().eq("user_id", user.id));
      check(
        await client.rpc("health_credentials_delete", {
          p_connection_id: connection.id,
        }),
      );
      if (token) {
        let response: Response;
        try {
          response = await fetch("https://oauth2.googleapis.com/revoke", {
            method: "POST",
            headers: { "Content-Type": "application/x-www-form-urlencoded" },
            body: new URLSearchParams({ token }),
            signal: AbortSignal.timeout(20000),
          });
        } catch {
          throw new HttpError(
            502,
            "RunTrack is disconnected and local tokens were deleted. Google revocation could not be confirmed; remove RunTrack in Google Account permissions.",
          );
        }
        if (!response.ok && response.status !== 400) {
          throw new HttpError(
            502,
            "RunTrack is disconnected and local tokens were deleted. Google revocation could not be confirmed; remove RunTrack in Google Account permissions.",
          );
        }
      }
      check(
        await client.from("sync_jobs").update({
          status: "succeeded",
          finished_at: new Date().toISOString(),
        }).eq("id", jobId),
      );
    } catch (error) {
      check(
        await client.from("sync_jobs").update({
          status: "failed",
          finished_at: new Date().toISOString(),
          error_message:
            "Disconnect could not fully finish. Check provider permissions.",
        }).eq("id", jobId),
      );
      throw error;
    }
  }
  return json(request, { status: "disconnected" });
}));
