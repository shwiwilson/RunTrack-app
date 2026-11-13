// This is operator tooling, intentionally outside supabase/functions. Deploy only
// with scripts/setup_health_delivery.py; the temporary endpoint is then removed.
export const PROJECT_REF = "cwdhymutbulafmtkfhqf";
export const PROJECT_ID = "runtrack-health-cwdhym";
export const PROJECT_NUMBER = "701191762202";
export const PROJECT_URL = `https://${PROJECT_REF}.supabase.co`;
export const SUBSCRIBER_ID = "runtrackexercise";
export const BOOTSTRAP_KEY = "RUNTRACK_HEALTH_BOOTSTRAP_TOKEN";
const WEBHOOK_URL = `${PROJECT_URL}/functions/v1/health-webhook`;
const GOOGLE_SUBSCRIBERS =
  `https://health.googleapis.com/v4/projects/${PROJECT_NUMBER}/subscribers`;
const MAX_BODY = 16384;

export class BridgeError extends Error {
  constructor(readonly status: number, readonly code: string) {
    super(code);
  }
}

export function validBootstrapToken(token: string, now: number): boolean {
  const match = /^rtboot1\.([0-9]{10})\.[A-Za-z0-9_-]{64}$/.exec(token);
  if (!match) return false;
  const expires = Number(match[1]);
  return expires > now && expires <= now + 900;
}

export async function constantTimeEqual(
  a: string,
  b: string,
): Promise<boolean> {
  const encode = new TextEncoder();
  const [left, right] = await Promise.all([
    crypto.subtle.digest("SHA-256", encode.encode(a)),
    crypto.subtle.digest("SHA-256", encode.encode(b)),
  ]);
  let difference = 0;
  const leftBytes = new Uint8Array(left), rightBytes = new Uint8Array(right);
  for (let i = 0; i < leftBytes.length; i++) {
    difference |= leftBytes[i] ^ rightBytes[i];
  }
  return difference === 0;
}

export async function nonceFingerprint(nonce: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(nonce),
  );
  return Array.from(
    new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}

export function validGoogleAccessToken(token: unknown): token is string {
  return typeof token === "string" &&
    /^[A-Za-z0-9._~+/=-]{20,4096}$/.test(token);
}

export function activeSubscriber(data: unknown): boolean {
  if (!data || typeof data !== "object") return false;
  const row = data as Record<string, unknown>;
  const names = [PROJECT_NUMBER, PROJECT_ID].map((id) =>
    `projects/${id}/subscribers/${SUBSCRIBER_ID}`
  );
  const authorization = row.endpointAuthorization as
    | Record<string, unknown>
    | undefined;
  const configs = row.subscriberConfigs;
  return names.includes(String(row.name)) && row.endpointUri === WEBHOOK_URL &&
    row.state === "ACTIVE" && authorization?.secretSet === true &&
    Array.isArray(configs) && configs.length === 1 &&
    configs[0]?.subscriptionCreatePolicy === "AUTOMATIC" &&
    Array.isArray(configs[0]?.dataTypes) && configs[0].dataTypes.length === 1 &&
    configs[0].dataTypes[0] === "exercise";
}

export function subscriberPayload(secret: string): Record<string, unknown> {
  return {
    endpointUri: WEBHOOK_URL,
    subscriberConfigs: [{
      dataTypes: ["exercise"],
      subscriptionCreatePolicy: "AUTOMATIC",
    }],
    endpointAuthorization: { secret: `Bearer ${secret}` },
  };
}

type Dependencies = {
  env: (name: string) => string;
  fetch: typeof fetch;
  now: () => number;
  sleep: (milliseconds: number) => Promise<void>;
};

async function readBody(request: Request): Promise<Record<string, unknown>> {
  if (
    !request.headers.get("content-type")?.toLowerCase().startsWith(
      "application/json",
    )
  ) {
    throw new BridgeError(400, "json_required");
  }
  const reader = request.body?.getReader();
  if (!reader) throw new BridgeError(400, "json_required");
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    size += value.length;
    if (size > MAX_BODY) {
      await reader.cancel();
      throw new BridgeError(413, "body_too_large");
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  try {
    const body = JSON.parse(
      new TextDecoder("utf-8", { fatal: true }).decode(bytes),
    );
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      throw new Error();
    }
    return body;
  } catch {
    throw new BridgeError(400, "invalid_json");
  }
}

function response(status: number, data: Record<string, unknown>): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json",
      "cache-control": "no-store",
    },
  });
}

export function createHandler(
  deps: Dependencies,
): (request: Request) => Promise<Response> {
  const request = (url: string, init: RequestInit) =>
    deps.fetch(url, {
      ...init,
      redirect: "error",
      signal: AbortSignal.timeout(15000),
    });
  const rpc = async (
    name: string,
    body: Record<string, string>,
  ): Promise<Record<string, unknown>> => {
    const service = deps.env("SUPABASE_SERVICE_ROLE_KEY");
    if (!service) throw new BridgeError(503, "server_configuration_missing");
    const result = await request(`${PROJECT_URL}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        apikey: service,
        authorization: `Bearer ${service}`,
      },
      body: JSON.stringify(body),
    });
    if (!result.ok) throw new BridgeError(502, "server_setup_rpc_failed");
    const data = await result.json();
    if (!data || typeof data !== "object" || Array.isArray(data)) {
      throw new BridgeError(502, "server_setup_readback_failed");
    }
    return data;
  };
  return async (incoming: Request): Promise<Response> => {
    try {
      if (incoming.method !== "POST") {
        throw new BridgeError(405, "post_required");
      }
      if (deps.env("SUPABASE_URL") !== PROJECT_URL) {
        throw new BridgeError(503, "wrong_runtime_project");
      }
      const nonce = deps.env(BOOTSTRAP_KEY);
      if (
        !validBootstrapToken(nonce, deps.now()) ||
        !(await constantTimeEqual(
          incoming.headers.get("authorization") ?? "",
          `Bearer ${nonce}`,
        ))
      ) {
        throw new BridgeError(401, "bootstrap_unauthorized");
      }
      const body = await readBody(incoming);
      if (body.project_ref !== PROJECT_REF) {
        throw new BridgeError(400, "wrong_target_project");
      }
      const allowed = body.action === "create-subscriber"
        ? ["project_ref", "action", "google_access_token"]
        : ["project_ref", "action"];
      if (Object.keys(body).some((key) => !allowed.includes(key))) {
        throw new BridgeError(400, "unexpected_fields");
      }
      if (body.action === "status") {
        const status = await rpc("runtrack_health_delivery_status", {
          p_nonce_sha256: await nonceFingerprint(nonce),
        });
        return response(200, {
          project_verified: true,
          google_oauth_configured: !!deps.env("GOOGLE_HEALTH_CLIENT_ID") &&
            !!deps.env("GOOGLE_HEALTH_CLIENT_SECRET"),
          scheduler_secret_present: !!deps.env("HEALTH_RECONCILE_SECRET"),
          webhook_secret_present: !!deps.env("GOOGLE_HEALTH_WEBHOOK_SECRET"),
          subscriber_active: status.subscriber_active === true,
          scheduler_enabled: status.scheduler_enabled === true,
          vault_secret_present: status.vault_secret_present === true,
        });
      }
      if (body.action === "install-scheduler") {
        const reconcile = deps.env("HEALTH_RECONCILE_SECRET");
        if (!reconcile) {
          throw new BridgeError(503, "scheduler_configuration_missing");
        }
        const installed = await rpc("install_runtrack_health_schedule", {
          p_reconcile_secret: reconcile,
        });
        if (
          installed.scheduler_enabled !== true ||
          installed.vault_secret_present !== true ||
          installed.schedule !== "* * * * *"
        ) {
          throw new BridgeError(502, "scheduler_verification_failed");
        }
        return response(200, {
          scheduler_enabled: true,
          vault_secret_present: true,
          schedule: "* * * * *",
        });
      }
      if (body.action === "create-subscriber") {
        const token = body.google_access_token;
        if (!validGoogleAccessToken(token)) {
          throw new BridgeError(400, "invalid_google_access_token");
        }
        const secret = deps.env("GOOGLE_HEALTH_WEBHOOK_SECRET");
        if (!secret) {
          throw new BridgeError(503, "webhook_configuration_missing");
        }
        const verificationBody = JSON.stringify({ type: "verification" });
        const authenticated = await request(WEBHOOK_URL, {
          method: "POST",
          headers: {
            "content-type": "application/json",
            authorization: `Bearer ${secret}`,
          },
          body: verificationBody,
        });
        const unauthenticated = await request(WEBHOOK_URL, {
          method: "POST",
          headers: {
            "content-type": "application/json",
          },
          body: verificationBody,
        });
        if (
          authenticated.status !== 201 ||
          ![401, 403].includes(unauthenticated.status)
        ) {
          throw new BridgeError(409, "webhook_verification_failed");
        }
        const headers = {
          "content-type": "application/json",
          authorization: `Bearer ${token}`,
        };
        const created = await request(
          `${GOOGLE_SUBSCRIBERS}?subscriberId=${SUBSCRIBER_ID}`,
          {
            method: "POST",
            headers,
            body: JSON.stringify(subscriberPayload(secret)),
          },
        );
        if (created.status === 409) {
          // Google's secret is input-only; an existing ACTIVE registration does
          // not prove it uses this runtime's bearer. Never overwrite it silently.
          throw new BridgeError(409, "subscriber_already_exists_review_required");
        }
        if (!created.ok) {
          throw new BridgeError(502, "subscriber_create_failed");
        }
        if (created.ok) {
          const operation = await created.json();
          if (operation?.error) {
            throw new BridgeError(502, "subscriber_operation_failed");
          }
        }
        // The API returns a long-running operation. Verify the actual resource
        // via documented list rather than treating an accepted operation as done.
        for (let attempt = 0; attempt < 10; attempt++) {
          const listed = await request(`${GOOGLE_SUBSCRIBERS}?pageSize=100`, {
            method: "GET",
            headers,
          });
          if (!listed.ok) {
            throw new BridgeError(502, "subscriber_readback_failed");
          }
          const result = await listed.json();
          if (
            Array.isArray(result.subscribers) &&
            result.subscribers.some(activeSubscriber)
          ) {
            const recorded = await rpc("record_runtrack_health_subscriber", {
              p_nonce_sha256: await nonceFingerprint(nonce),
            });
            if (recorded.subscriber_active !== true) {
              throw new BridgeError(502, "subscriber_status_record_failed");
            }
            return response(200, {
              subscriber_active: true,
              webhook_verified: true,
              subscriber_name:
                `projects/${PROJECT_NUMBER}/subscribers/${SUBSCRIBER_ID}`,
            });
          }
          if (attempt < 9) await deps.sleep(1000);
        }
        throw new BridgeError(502, "subscriber_not_active_yet");
      }
      throw new BridgeError(400, "unknown_action");
    } catch (error) {
      // Never forward external response bodies, exceptions, credentials or tokens.
      return error instanceof BridgeError
        ? response(error.status, { error: error.code })
        : response(502, { error: "bootstrap_request_failed" });
    }
  };
}
