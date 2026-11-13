import {
  activeSubscriber,
  BOOTSTRAP_KEY,
  constantTimeEqual,
  createHandler,
  nonceFingerprint,
  PROJECT_NUMBER,
  PROJECT_REF,
  PROJECT_URL,
  subscriberPayload,
  validBootstrapToken,
  validGoogleAccessToken,
} from "./bridge.ts";

function assert(
  condition: unknown,
  message = "assertion failed",
): asserts condition {
  if (!condition) throw new Error(message);
}
const NOW = 1800000000;
const NONCE = `rtboot1.${NOW + 900}.${"n".repeat(64)}`;
const RECONCILE = "fixture-reconciliation-secret-32bytes";
const WEBHOOK = "fixture-webhook-secret-32bytes";
const SERVICE = "fixture-service-role-key-32bytes";
const GOOGLE = "ya29.fixtureShortLivedGoogleToken";
const RUNTIME: Record<string, string> = {
  SUPABASE_URL: PROJECT_URL,
  [BOOTSTRAP_KEY]: NONCE,
  HEALTH_RECONCILE_SECRET: RECONCILE,
  GOOGLE_HEALTH_WEBHOOK_SECRET: WEBHOOK,
  SUPABASE_SERVICE_ROLE_KEY: SERVICE,
  GOOGLE_HEALTH_CLIENT_ID: "fixture.apps.googleusercontent.com",
  GOOGLE_HEALTH_CLIENT_SECRET: "fixture-google-client-secret",
};
function incoming(
  action: string,
  extra: Record<string, unknown> = {},
  authorization = `Bearer ${NONCE}`,
): Request {
  return new Request(`${PROJECT_URL}/functions/v1/setup-health-bootstrap`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization },
    body: JSON.stringify({ project_ref: PROJECT_REF, action, ...extra }),
  });
}
function active() {
  return {
    name: `projects/${PROJECT_NUMBER}/subscribers/runtrackexercise`,
    endpointUri: `${PROJECT_URL}/functions/v1/health-webhook`,
    state: "ACTIVE",
    endpointAuthorization: { secretSet: true },
    subscriberConfigs: [{
      dataTypes: ["exercise"],
      subscriptionCreatePolicy: "AUTOMATIC",
    }],
  };
}
function deps(fetcher: typeof fetch, runtime = RUNTIME) {
  return {
    env: (key: string) => runtime[key] ?? "",
    fetch: fetcher,
    now: () => NOW,
    sleep: (_milliseconds: number) => Promise.resolve(),
  };
}
const noFetch: typeof fetch = () => {
  throw new Error("Unexpected outbound request");
};

Deno.test("bootstrap nonce has a bounded lifetime and exact shape", () => {
  assert(validBootstrapToken(NONCE, NOW));
  assert(!validBootstrapToken(NONCE, NOW + 900));
  assert(!validBootstrapToken(NONCE, NOW - 1));
  assert(!validBootstrapToken("rtboot1.1800000900.short", NOW));
  assert(!validBootstrapToken(NONCE + "\n", NOW));
});
Deno.test("constant-time comparison checks entire values", async () => {
  assert(await constantTimeEqual(NONCE, NONCE));
  assert(!(await constantTimeEqual(NONCE, NONCE.slice(0, -1) + "x")));
  assert(!(await constantTimeEqual(NONCE, "")));
});
Deno.test("setup status fingerprint is deterministic and does not persist nonce", async () => {
  const fingerprint = await nonceFingerprint(NONCE);
  assert(/^[a-f0-9]{64}$/.test(fingerprint));
  assert(fingerprint === await nonceFingerprint(NONCE));
  assert(fingerprint !== await nonceFingerprint(NONCE + "x"));
});
Deno.test("IAM token input rejects whitespace, payloads, and excessive length", () => {
  assert(validGoogleAccessToken(GOOGLE));
  for (
    const invalid of [
      "short",
      " ".repeat(32),
      GOOGLE + "\n",
      GOOGLE + " secret",
      "a".repeat(4097),
      {},
      null,
    ]
  ) {
    assert(!validGoogleAccessToken(invalid));
  }
});
Deno.test("subscriber readiness requires exact resource, endpoint, exercise-only automatic policy, active state and configured secret", () => {
  assert(activeSubscriber(active()));
  assert(
    !activeSubscriber({ ...active(), endpointUri: "https://example.com" }),
  );
  assert(!activeSubscriber({ ...active(), state: "UNVERIFIED" }));
  assert(
    !activeSubscriber({
      ...active(),
      endpointAuthorization: { secretSet: false },
    }),
  );
  assert(
    !activeSubscriber({
      ...active(),
      name: "projects/other/subscribers/runtrackexercise",
    }),
  );
  assert(
    !activeSubscriber({
      ...active(),
      subscriberConfigs: [{
        dataTypes: ["exercise", "sleep"],
        subscriptionCreatePolicy: "AUTOMATIC",
      }],
    }),
  );
});
Deno.test("subscriber payload contains existing bearer only in authorization field", () => {
  const payload = subscriberPayload(WEBHOOK);
  assert(
    (payload.endpointAuthorization as { secret: string }).secret ===
      `Bearer ${WEBHOOK}`,
  );
  assert(payload.endpointUri === `${PROJECT_URL}/functions/v1/health-webhook`);
});
Deno.test("unauthorized requests make no outbound calls", async () => {
  const handler = createHandler(deps(noFetch));
  const result = await handler(incoming("status", {}, "Bearer wrong"));
  assert(result.status === 401);
  assert(!(await result.text()).includes(NONCE));
});
Deno.test("wrong runtime and target projects fail closed", async () => {
  const wrongRuntime = createHandler(
    deps(noFetch, { ...RUNTIME, SUPABASE_URL: "https://other.supabase.co" }),
  );
  assert((await wrongRuntime(incoming("status"))).status === 503);
  const handler = createHandler(deps(noFetch));
  assert(
    (await handler(incoming("status", { project_ref: "other" }))).status ===
      400,
  );
});
Deno.test("status returns booleans only and never server secret values", async () => {
  const result = await createHandler(deps((url, init) => {
    assert(
      url === `${PROJECT_URL}/rest/v1/rpc/runtrack_health_delivery_status`,
    );
    assert(
      /^[a-f0-9]{64}$/.test(JSON.parse(String(init?.body)).p_nonce_sha256),
    );
    return Promise.resolve(
      Response.json({
        subscriber_active: false,
        scheduler_enabled: false,
        vault_secret_present: false,
      }),
    );
  }))(incoming("status"));
  assert(result.status === 200);
  const raw = await result.text();
  for (const secret of [NONCE, RECONCILE, WEBHOOK, SERVICE, GOOGLE]) {
    assert(!raw.includes(secret));
  }
  const body = JSON.parse(raw);
  assert(Object.values(body).every((value) => typeof value === "boolean"));
});
Deno.test("oversized and unexpected input fail before outbound calls", async () => {
  const handler = createHandler(deps(noFetch));
  assert(
    (await handler(incoming("status", { unexpected: true }))).status === 400,
  );
  assert(
    (await handler(incoming("status", { huge: "x".repeat(16384) }))).status ===
      413,
  );
  assert((await handler(incoming("delete-everything"))).status === 400);
});
Deno.test("scheduler sends the existing secret only to the fixed service-only RPC and returns safe readback", async () => {
  let calls = 0;
  const handler = createHandler(deps((url, init) => {
    calls++;
    assert(
      url === `${PROJECT_URL}/rest/v1/rpc/install_runtrack_health_schedule`,
    );
    assert(init?.method === "POST" && init.redirect === "error");
    assert(new Headers(init.headers).get("apikey") === SERVICE);
    assert(JSON.parse(String(init.body)).p_reconcile_secret === RECONCILE);
    return Promise.resolve(
      Response.json({
        scheduler_enabled: true,
        vault_secret_present: true,
        schedule: "* * * * *",
      }),
    );
  }));
  const result = await handler(incoming("install-scheduler"));
  assert(result.status === 200 && calls === 1);
  const raw = await result.text();
  assert(!raw.includes(RECONCILE) && !raw.includes(SERVICE));
});
Deno.test("upstream failures never echo provider body or exceptions", async () => {
  const handler = createHandler(
    deps(() => Promise.reject(new Error(RECONCILE + SERVICE))),
  );
  const result = await handler(incoming("install-scheduler"));
  assert(result.status === 502);
  const raw = await result.text();
  assert(!raw.includes(RECONCILE) && !raw.includes(SERVICE));
  const denied = createHandler(
    deps(() => Promise.resolve(new Response(WEBHOOK, { status: 400 }))),
  );
  const deniedResult = await denied(incoming("install-scheduler"));
  assert(!(await deniedResult.text()).includes(WEBHOOK));
});
Deno.test("subscriber requires both handshake outcomes then verifies actual ACTIVE resource", async () => {
  let call = 0;
  const handler = createHandler(deps((url, init) => {
    call++;
    if (call <= 2) {
      assert(url === `${PROJECT_URL}/functions/v1/health-webhook`);
      const header = new Headers(init?.headers).get("authorization");
      assert(call === 1 ? header === `Bearer ${WEBHOOK}` : header === null);
      return Promise.resolve(
        new Response(null, { status: call === 1 ? 201 : 401 }),
      );
    }
    if (call === 5) {
      assert(
        url === `${PROJECT_URL}/rest/v1/rpc/record_runtrack_health_subscriber`,
      );
      assert(
        /^[a-f0-9]{64}$/.test(JSON.parse(String(init?.body)).p_nonce_sha256),
      );
      return Promise.resolve(Response.json({ subscriber_active: true }));
    }
    assert(
      String(url).startsWith(
        `https://health.googleapis.com/v4/projects/${PROJECT_NUMBER}/subscribers`,
      ),
    );
    assert(
      new Headers(init?.headers).get("authorization") === `Bearer ${GOOGLE}`,
    );
    if (call === 3) {
      assert(init?.method === "POST");
      assert(
        JSON.parse(String(init?.body)).endpointAuthorization.secret ===
          `Bearer ${WEBHOOK}`,
      );
      return Promise.resolve(
        Response.json({ done: false, name: "operations/fixture" }),
      );
    }
    assert(init?.method === "GET");
    return Promise.resolve(Response.json({ subscribers: [active()] }));
  }));
  const result = await handler(
    incoming("create-subscriber", { google_access_token: GOOGLE }),
  );
  assert(result.status === 200 && call === 5);
  const raw = await result.text();
  assert(
    !raw.includes(GOOGLE) && !raw.includes(WEBHOOK) && !raw.includes(NONCE),
  );
});
Deno.test("failed webhook verification prevents Google subscriber creation", async () => {
  let calls = 0;
  const handler = createHandler(deps((url) => {
    calls++;
    assert(url === `${PROJECT_URL}/functions/v1/health-webhook`);
    return Promise.resolve(new Response(null, { status: 200 }));
  }));
  const result = await handler(
    incoming("create-subscriber", { google_access_token: GOOGLE }),
  );
  assert(result.status === 409 && calls === 2);
});
Deno.test("accepted but inactive subscriber is not reported as complete", async () => {
  let call = 0;
  const handler = createHandler(deps(() => {
    call++;
    if (call <= 2) {
      return Promise.resolve(
        new Response(null, { status: call === 1 ? 201 : 401 }),
      );
    }
    if (call === 3) return Promise.resolve(Response.json({ done: false }));
    return Promise.resolve(
      Response.json({ subscribers: [{ ...active(), state: "UNVERIFIED" }] }),
    );
  }));
  const result = await handler(
    incoming("create-subscriber", { google_access_token: GOOGLE }),
  );
  assert(result.status === 502 && call === 13);
  assert((await result.json()).error === "subscriber_not_active_yet");
});

Deno.test("existing subscriber conflict never silently replaces or certifies a different secret", async () => {
  let call = 0;
  const handler = createHandler(deps(() => {
    call++;
    if (call <= 2) {
      return Promise.resolve(
        new Response(null, { status: call === 1 ? 201 : 401 }),
      );
    }
    return Promise.resolve(
      new Response("provider response withheld", { status: 409 }),
    );
  }));
  const result = await handler(
    incoming("create-subscriber", { google_access_token: GOOGLE }),
  );
  assert(result.status === 409 && call === 3);
  assert(
    (await result.json()).error === "subscriber_already_exists_review_required",
  );
});
