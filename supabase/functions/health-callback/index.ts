import {
  decrypt,
  GOOGLE_HEALTH_API,
  linkedHealthIdentity,
  sha256,
} from "../_shared/health_core.ts";
import {
  check,
  configurationRequired,
  env,
  handled,
  HttpError,
  providerJson,
  requireHealthConsent,
  serviceClient,
  storeTokens,
  syncConnection,
} from "../_shared/health_runtime.ts";
async function callback(request: Request): Promise<Response> {
  if (request.method !== "GET") throw new HttpError(405, "Use GET.");
  if (configurationRequired().length) {
    throw new HttpError(503, "Google Health setup is incomplete.");
  }
  const url = new URL(request.url), state = url.searchParams.get("state") ?? "";
  if (!/^[A-Za-z0-9_-]{43}$/.test(state)) {
    throw new HttpError(
      400,
      "This connection request is invalid. Start again from RunTrack.",
    );
  }
  const client = serviceClient(), hash = await sha256(state);
  const record = check(
    await client.rpc("consume_health_oauth_state", { p_hash: hash }),
  );
  if (!record || record.redirect_uri !== env("GOOGLE_HEALTH_REDIRECT_URI")) {
    throw new HttpError(
      400,
      "This connection request expired or was already used. Start again from RunTrack.",
    );
  }
  const redirect = new URL(env("APP_URL"));
  redirect.searchParams.set("health", "return");
  if (url.searchParams.has("error")) {
    redirect.searchParams.set("health_result", "cancelled");
    return Response.redirect(redirect, 303);
  }
  const code = url.searchParams.get("code");
  if (!code) {
    throw new HttpError(400, "Google did not return an authorization code.");
  }
  // Identity comes from the original genuine, verified Supabase user, never callback parameters.
  const { data, error } = await client.auth.admin.getUserById(record.user_id);
  if (error || !data.user?.email_confirmed_at) {
    throw new HttpError(401, "The initiating account is unavailable.");
  }
  if (!Number.isSafeInteger(record.health_consent_id)) {
    throw new HttpError(
      403,
      "Start again from RunTrack and review the health data consent.",
    );
  }
  await requireHealthConsent(client, record.user_id, record.health_consent_id);
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code,
      client_id: env("GOOGLE_HEALTH_CLIENT_ID"),
      client_secret: env("GOOGLE_HEALTH_CLIENT_SECRET"),
      redirect_uri: record.redirect_uri,
      grant_type: "authorization_code",
      code_verifier: await decrypt(
        record.code_verifier_ciphertext,
        env("HEALTH_TOKEN_ENCRYPTION_KEY"),
        hash,
      ),
    }),
    signal: AbortSignal.timeout(20000),
  });
  if (!response.ok) {
    throw new HttpError(
      400,
      "Google could not authorize this connection. Start again from RunTrack.",
    );
  }
  const tokens = await response.json();
  const identity = linkedHealthIdentity(
    await providerJson(
      `${GOOGLE_HEALTH_API}/users/me/identity`,
      tokens.access_token,
    ),
  );
  let connection = check(
    await client.from("health_connections").select("*").eq(
      "user_id",
      record.user_id,
    ).eq("provider", "google_health").maybeSingle(),
  );
  if (!connection) {
    connection = check(
      await client.from("health_connections").insert({
        user_id: record.user_id,
        provider: "google_health",
        status: "error",
      }).select().single(),
    );
  }
  // Reserve the same per-connection lease used by syncs before replacing any credentials.
  const jobId = check(
    await client.rpc("claim_health_sync", { p_connection_id: connection.id }),
  );
  if (!jobId) {
    throw new HttpError(
      409,
      "A workout sync is running. Wait a moment before reconnecting.",
    );
  }
  try {
    const activeState = check(
      await client.from("oauth_states").select("state_hash").eq(
        "state_hash",
        hash,
      ).eq("user_id", record.user_id).maybeSingle(),
    );
    if (!activeState) {
      throw new HttpError(
        409,
        "Connection was cancelled. Start again from RunTrack.",
      );
    }
    await requireHealthConsent(
      client,
      record.user_id,
      record.health_consent_id,
    );
    check(
      await client.from("health_connections").update({
        status: "error",
        last_error: null,
      }).eq("id", connection.id),
    );
    await storeTokens(client, connection.id, tokens);
    connection = check(
      await client.from("health_connections").update({
        provider_user_id: identity,
        sync_cursor: {},
        status: "connected",
        last_error: null,
      }).eq("id", connection.id).in("status", ["connected", "error"]).select()
        .single(),
    );
    const result = await syncConnection(client, connection, true, jobId);
    redirect.searchParams.set(
      "health_result",
      result.complete ? "linked" : "partial",
    );
  } catch (error) {
    check(
      await client.from("sync_jobs").update({
        status: "failed",
        finished_at: new Date().toISOString(),
        error_message: "Connection could not finish. Retry.",
      }).eq("id", jobId),
    );
    check(
      await client.from("health_connections").update({
        status: "error",
        last_error: error instanceof HttpError
          ? error.message
          : "Connection could not finish. Please retry.",
      }).eq("id", connection.id).in("status", ["connected", "error"]),
    );
    redirect.searchParams.set("health_result", "retry");
  }
  return Response.redirect(redirect, 303);
}
Deno.serve(handled(async (request) => {
  try {
    return await callback(request);
  } catch (error) {
    if (!env("APP_URL")) throw error;
    const redirect = new URL(env("APP_URL"));
    redirect.searchParams.set("health", "return");
    redirect.searchParams.set(
      "health_result",
      error instanceof HttpError && error.status === 409
        ? "check_health_profile"
        : "authorization_failed",
    );
    return Response.redirect(redirect, 303);
  }
}));
