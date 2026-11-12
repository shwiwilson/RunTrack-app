import { createClient } from "npm:@supabase/supabase-js@2.119.0";
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

// The password is checked by Auth against the verified identity from the access
// token; a caller cannot select a different victim using request fields.
Deno.serve(handled(async (request) => {
  if (request.method !== "POST") throw new HttpError(405, "Use POST.");
  const service = serviceClient();
  const user = await requireUser(request, service);
  const body = await request.json();
  if (
    body.confirmation !== "DELETE" || typeof body.password !== "string" ||
    !body.password || body.password.length > 1024
  ) {
    throw new HttpError(
      400,
      "Confirm deletion and enter your current password.",
    );
  }
  const verifier = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const result = await verifier.auth.signInWithPassword({
    email: user.email!,
    password: body.password,
  });
  if (result.error || result.data.user?.id !== user.id) {
    throw new HttpError(403, "Your current password is required.");
  }
  await verifier.auth.signOut().catch(() => undefined);
  const connections = check(
    await service.from("health_connections").select("id").eq(
      "user_id",
      user.id,
    ),
  ) ?? [];
  for (const connection of connections) {
    const credentials = check(
      await service.rpc("health_credentials_get", {
        p_connection_id: connection.id,
      }),
    );
    if (credentials && env("HEALTH_TOKEN_ENCRYPTION_KEY")) {
      try {
        const token = await decrypt(
          credentials.refresh_token_ciphertext ??
            credentials.access_token_ciphertext,
          env("HEALTH_TOKEN_ENCRYPTION_KEY"),
          connection.id,
        );
        await fetch("https://oauth2.googleapis.com/revoke", {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body: new URLSearchParams({ token }),
          signal: AbortSignal.timeout(10000),
        });
      } catch {
        /* Erasure must still proceed if Google's revoke service is down. */
      }
    }
  }
  const deletion = await service.auth.admin.deleteUser(user.id);
  if (deletion.error) throw new Error("Account deletion failed");
  return json(request, { deleted: true });
}));
