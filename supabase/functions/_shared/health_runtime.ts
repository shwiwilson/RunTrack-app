import {
  createClient,
  type SupabaseClient,
} from "npm:@supabase/supabase-js@2.119.0";
import {
  decrypt,
  encrypt,
  GOOGLE_HEALTH_API,
  GOOGLE_HEALTH_SCOPE,
  linkedHealthIdentity,
  needsTokenRefresh,
  normaliseGoogleWorkout,
} from "./health_core.ts";
export const env = (name: string): string => Deno.env.get(name) ?? "";
export class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}
export function configurationRequired(): string[] {
  return [
    "SUPABASE_URL",
    "SUPABASE_SERVICE_ROLE_KEY",
    "GOOGLE_HEALTH_CLIENT_ID",
    "GOOGLE_HEALTH_CLIENT_SECRET",
    "GOOGLE_HEALTH_REDIRECT_URI",
    "HEALTH_TOKEN_ENCRYPTION_KEY",
    "APP_URL",
  ].filter((name) => !env(name));
}
export function serviceClient(): SupabaseClient {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
export function cors(request: Request): HeadersInit {
  const origin = env("APP_URL") ? new URL(env("APP_URL")).origin : "";
  return {
    "Access-Control-Allow-Origin": request.headers.get("origin") === origin
      ? origin
      : "null",
    "Access-Control-Allow-Headers":
      "authorization,x-client-info,apikey,content-type",
    "Access-Control-Allow-Methods": "POST,OPTIONS",
    "Vary": "Origin",
    "Cache-Control": "no-store",
  };
}
export const json = (request: Request, body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors(request), "Content-Type": "application/json" },
  });
export async function requireUser(request: Request, client: SupabaseClient) {
  const token = (request.headers.get("authorization") ?? "").replace(
    /^Bearer\s+/i,
    "",
  );
  if (!token) throw new HttpError(401, "Sign in to connect your running data.");
  const { data, error } = await client.auth.getUser(token);
  if (error || !data.user || !data.user.email_confirmed_at) {
    throw new HttpError(401, "A verified signed-in account is required.");
  }
  return data.user;
}
export function check<T>(
  result: { data: T; error: { message: string } | null },
): T {
  if (result.error) throw new Error("Database operation failed"); // never log payloads or credentials
  return result.data;
}
export async function requireHealthConsent(
  client: SupabaseClient,
  userId: string,
  consentId?: number,
): Promise<void> {
  const active = check(
    await client.rpc("health_consent_active", {
      p_user_id: userId,
      p_consent_id: consentId ?? null,
    }),
  );
  if (active !== true) {
    throw new HttpError(
      403,
      "Health data consent is missing or withdrawn. Review the consent and reconnect Google Health.",
    );
  }
}
export const handled =
  (handler: (request: Request) => Promise<Response>) =>
  async (request: Request) => {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors(request) });
    }
    try {
      return await handler(request);
    } catch (error) {
      return json(request, {
        error: error instanceof HttpError
          ? error.message
          : "The running data service could not complete this request. Please retry.",
      }, error instanceof HttpError ? error.status : 502);
    }
  };
export async function providerJson(
  url: string,
  token: string,
): Promise<Record<string, unknown>> {
  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${token}`, Accept: "application/json" },
    signal: AbortSignal.timeout(20000),
  });
  if (response.status === 401 || response.status === 403) {
    throw new HttpError(
      401,
      "Google Health permission expired or was revoked. Reconnect your account.",
    );
  }
  if (!response.ok) {
    const error = await response.json().catch(() => ({}));
    const serialized = JSON.stringify(error);
    if (serialized.includes("ACCOUNT_NOT_LINKED")) {
      throw new HttpError(
        409,
        "Open the Google Health mobile app and link this Google Account before reconnecting.",
      );
    }
    throw new HttpError(
      502,
      "Google Health is currently unable to provide your workouts. Please retry.",
    );
  }
  return await response.json();
}
export async function storeTokens(
  client: SupabaseClient,
  connectionId: string,
  tokens: Record<string, unknown>,
  previousRefresh?: string,
) {
  if (typeof tokens.access_token !== "string") {
    throw new Error("No provider access token");
  }
  const refresh = typeof tokens.refresh_token === "string"
    ? tokens.refresh_token
    : previousRefresh;
  if (!refresh) {
    throw new HttpError(
      409,
      "Google did not grant offline access. Reconnect and approve running data access.",
    );
  }
  const expiresIn = Number(tokens.expires_in);
  if (!Number.isFinite(expiresIn) || expiresIn <= 0) {
    throw new Error("Invalid provider expiry");
  }
  const scopes = typeof tokens.scope === "string"
    ? tokens.scope.split(" ")
    : [GOOGLE_HEALTH_SCOPE];
  if (!scopes.includes(GOOGLE_HEALTH_SCOPE)) {
    throw new HttpError(403, "Running data permission was not granted.");
  }
  check(
    await client.rpc("health_credentials_store", {
      p_connection_id: connectionId,
      p_access_token_ciphertext: await encrypt(
        tokens.access_token,
        env("HEALTH_TOKEN_ENCRYPTION_KEY"),
        connectionId,
      ),
      p_refresh_token_ciphertext: await encrypt(
        refresh,
        env("HEALTH_TOKEN_ENCRYPTION_KEY"),
        connectionId,
      ),
      p_expires_at: new Date(Date.now() + expiresIn * 1000).toISOString(),
      p_scopes: scopes,
    }),
  );
}
export async function accessToken(
  client: SupabaseClient,
  connectionId: string,
): Promise<string> {
  const credentials = check(
    await client.rpc("health_credentials_get", {
      p_connection_id: connectionId,
    }),
  );
  if (!credentials) {
    throw new HttpError(409, "Connect Google Health before syncing workouts.");
  }
  if (!needsTokenRefresh(credentials.expires_at)) {
    return decrypt(
      credentials.access_token_ciphertext,
      env("HEALTH_TOKEN_ENCRYPTION_KEY"),
      connectionId,
    );
  }
  const refresh = await decrypt(
    credentials.refresh_token_ciphertext,
    env("HEALTH_TOKEN_ENCRYPTION_KEY"),
    connectionId,
  );
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: env("GOOGLE_HEALTH_CLIENT_ID"),
      client_secret: env("GOOGLE_HEALTH_CLIENT_SECRET"),
      refresh_token: refresh,
      grant_type: "refresh_token",
    }),
    signal: AbortSignal.timeout(20000),
  });
  if (!response.ok) {
    if (response.status === 400 || response.status === 401) {
      const connection = check(
        await client.from("health_connections").select("user_id")
          .eq("id", connectionId).single(),
      );
      if (!connection) {
        throw new HttpError(409, "Health connection is unavailable.");
      }
      check(
        await client.rpc("withdraw_health_consent", {
          p_user_id: connection.user_id,
          p_reason: "provider_revoked",
        }),
      );
      throw new HttpError(
        401,
        "Google Health permission expired or was revoked. Reconnect your account.",
      );
    }
    throw new HttpError(
      502,
      "Google could not renew access. Please retry later.",
    );
  }
  const tokens = await response.json();
  await storeTokens(client, connectionId, tokens, refresh);
  return tokens.access_token;
}
export async function syncConnection(
  client: SupabaseClient,
  connection: Record<string, unknown>,
  full = false,
  reservedJobId?: string,
): Promise<{ imported: number; complete: boolean }> {
  const connectionId = String(connection.id);
  await requireHealthConsent(client, String(connection.user_id));
  const jobId = reservedJobId ?? check(
    await client.rpc("claim_health_sync", { p_connection_id: connectionId }),
  );
  if (!jobId) {
    throw new HttpError(
      409,
      "A sync is already running. Please retry shortly.",
    );
  }
  try {
    const token = await accessToken(client, connectionId);
    const identity = linkedHealthIdentity(
      await providerJson(`${GOOGLE_HEALTH_API}/users/me/identity`, token),
    );
    if (identity !== connection.provider_user_id) {
      throw new HttpError(
        409,
        "Google Health account changed. Reconnect your account.",
      );
    }
    const cursor = connection.sync_cursor as Record<string, unknown> | null;
    const resuming = typeof cursor?.pending_page === "string";
    const isFull = resuming
      ? cursor?.pending_full === true
      : full || !cursor?.last_sync;
    const syncStarted = resuming
      ? String(cursor?.pending_started)
      : new Date().toISOString();
    const from = resuming
      ? (typeof cursor?.pending_from === "string" ? cursor.pending_from : null)
      : !isFull && typeof cursor?.last_sync === "string"
      ? new Date(Date.parse(cursor.last_sync) - 7 * 86400000).toISOString()
      : null;
    let nextPage = resuming ? String(cursor?.pending_page) : "",
      imported = 0,
      pages = 0;
    do {
      await requireHealthConsent(client, String(connection.user_id));
      const url = new URL(
        `${GOOGLE_HEALTH_API}/users/me/dataTypes/exercise/dataPoints:reconcile`,
      );
      url.searchParams.set("pageSize", "25");
      if (from) {
        url.searchParams.set(
          "filter",
          `exercise.interval.start_time >= "${from}"`,
        );
      }
      if (nextPage) url.searchParams.set("pageToken", nextPage);
      const response = await providerJson(url.toString(), token);
      for (
        const item of Array.isArray(response.dataPoints)
          ? response.dataPoints
          : []
      ) {
        if (!item || typeof item !== "object") continue;
        let normalized = normaliseGoogleWorkout(
          item as Record<string, unknown>,
          String(connection.user_id),
        );
        if (!normalized) continue;
        if (!(item as Record<string, unknown>).dataSource) {
          // Reconcile selects one workout across overlapping sources. Fetch that exact
          // stable resource for available device and provenance metadata, never routes.
          const rawPoint = await providerJson(
            `${GOOGLE_HEALTH_API}/${normalized.activity.provider_workout_id}`,
            token,
          );
          normalized = normaliseGoogleWorkout({
            ...rawPoint,
            dataPointName: normalized.activity.provider_workout_id,
          }, String(connection.user_id));
          if (!normalized) continue;
        }
        check(
          await client.rpc("upsert_health_activity", {
            p_activity: normalized.activity,
            p_laps: normalized.laps,
          }),
        );
        imported++;
      }
      nextPage = typeof response.nextPageToken === "string"
        ? response.nextPageToken
        : "";
      if (++pages >= 2 && nextPage) break;
    } while (nextPage);
    const complete = !nextPage;
    // Full reconciliations remove only records no longer present at the provider, after every
    // page succeeds. A partial/error sync never deletes history or advances its success time.
    if (complete && isFull) {
      check(
        await client.rpc("reconcile_health_deletions", {
          p_connection_id: connectionId,
          p_seen_before: syncStarted,
        }),
      );
    }
    const newCursor = complete
      ? {
        last_sync: syncStarted,
        last_full_sync: isFull ? syncStarted : cursor?.last_full_sync ?? null,
      }
      : {
        ...cursor,
        pending_page: nextPage,
        pending_full: isFull,
        pending_started: syncStarted,
        pending_from: from,
      };
    const updatedConnection = check(
      await client.from("health_connections").update({
        status: "connected",
        last_error: null,
        sync_cursor: newCursor,
        ...(complete ? { last_successful_sync_at: syncStarted } : {}),
      }).eq("id", connectionId).eq("provider_user_id", identity).in("status", [
        "connected",
        "error",
      ]).select("id").maybeSingle(),
    );
    if (!updatedConnection) {
      throw new HttpError(
        409,
        "Connection changed or was disconnected during sync. Reconnect before retrying.",
      );
    }
    if (complete) {
      check(
        await client.from("sync_events").update({
          processed_at: new Date().toISOString(),
        }).eq("connection_id", connectionId).is("processed_at", null).lte(
          "received_at",
          syncStarted,
        ),
      );
    }
    check(
      await client.from("sync_jobs").update({
        status: "succeeded",
        finished_at: new Date().toISOString(),
      }).eq("id", jobId),
    );
    return { imported, complete };
  } catch (error) {
    check(
      await client.from("sync_jobs").update({
        status: "failed",
        finished_at: new Date().toISOString(),
        error_message: error instanceof HttpError
          ? error.message
          : "Sync failed; retry safely.",
      }).eq("id", jobId),
    );
    throw error;
  }
}
