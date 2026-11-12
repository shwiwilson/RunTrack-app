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
  // Withdrawal, token deletion, state cancellation and local disconnection are
  // one transaction. A running sync cannot postpone withdrawal.
  const credentials = check(
    await client.rpc("withdraw_health_consent", {
      p_user_id: user.id,
      p_reason: "disconnect",
    }),
  );
  if (credentials?.refresh_token_ciphertext) {
    try {
      const token = await decrypt(
        credentials.refresh_token_ciphertext,
        env("HEALTH_TOKEN_ENCRYPTION_KEY"),
        credentials.connection_id,
      );
      const response = await fetch("https://oauth2.googleapis.com/revoke", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ token }),
        signal: AbortSignal.timeout(20000),
      });
      if (!response.ok && response.status !== 400) {
        throw new Error("Revocation unavailable");
      }
    } catch {
      throw new HttpError(
        502,
        "RunTrack is disconnected, health consent was withdrawn and local tokens were deleted. Google revocation could not be confirmed; remove RunTrack in Google Account permissions.",
      );
    }
  }
  return json(request, { status: "disconnected" });
}));
