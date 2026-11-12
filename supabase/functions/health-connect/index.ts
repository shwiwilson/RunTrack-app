import {
  encrypt,
  GOOGLE_HEALTH_SCOPE,
  randomSecret,
  sha256,
} from "../_shared/health_core.ts";
import {
  check,
  configurationRequired,
  env,
  handled,
  HttpError,
  json,
  requireUser,
  serviceClient,
} from "../_shared/health_runtime.ts";
import { validateHealthConsent } from "../_shared/health_consent.ts";
Deno.serve(handled(async (request) => {
  if (request.method !== "POST") throw new HttpError(405, "Use POST.");
  const client = serviceClient(), user = await requireUser(request, client);
  const consent = await request.json().catch(() => null);
  validateHealthConsent(consent);
  if (configurationRequired().length) {
    return json(request, {
      status: "setup_required",
      message:
        "Google Health is awaiting secure deployment configuration. You can connect later.",
    });
  }
  const state = randomSecret(),
    hash = await sha256(state),
    verifier = randomSecret();
  const { count, error } = await client.from("oauth_states").select(
    "state_hash",
    { count: "exact", head: true },
  ).eq("user_id", user.id).gt("expires_at", new Date().toISOString());
  if (error) throw new Error("Database operation failed");
  if ((count ?? 0) >= 5) {
    throw new HttpError(
      429,
      "Several connections were started recently. Please wait ten minutes and retry.",
    );
  }
  // The verified server identity and database clock are the evidence, never a
  // user ID or timestamp submitted by the browser.
  const consentId = check(
    await client.rpc("record_health_consent", {
      p_user_id: user.id,
      p_consent_version: consent.consent_version,
    }),
  );
  check(
    await client.from("oauth_states").insert({
      state_hash: hash,
      user_id: user.id,
      health_consent_id: consentId,
      expires_at: new Date(Date.now() + 10 * 60000).toISOString(),
      redirect_uri: env("GOOGLE_HEALTH_REDIRECT_URI"),
      code_verifier_ciphertext: await encrypt(
        verifier,
        env("HEALTH_TOKEN_ENCRYPTION_KEY"),
        hash,
      ),
    }),
  );
  const url = new URL("https://accounts.google.com/o/oauth2/v2/auth");
  Object.entries({
    client_id: env("GOOGLE_HEALTH_CLIENT_ID"),
    redirect_uri: env("GOOGLE_HEALTH_REDIRECT_URI"),
    response_type: "code",
    access_type: "offline",
    scope: GOOGLE_HEALTH_SCOPE,
    prompt: "consent",
    state,
    code_challenge: await sha256(verifier),
    code_challenge_method: "S256",
  }).forEach(([key, value]) => url.searchParams.set(key, value));
  return json(request, { authorization_url: url.toString() });
}));
