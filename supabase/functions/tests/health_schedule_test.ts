import type { SupabaseClient } from "npm:@supabase/supabase-js@2.119.0";
import { base64, encrypt } from "../_shared/health_core.ts";
import { syncConnection } from "../_shared/health_runtime.ts";
import {
  HealthSyncBudget,
  retryAfterTime,
  runHealthBatch,
} from "../_shared/health_sync_budget.ts";
function assert(value: unknown, message = "Assertion failed"): asserts value {
  if (!value) throw new Error(message);
}
Deno.test("scheduler keeps oldest-first start order, bounds concurrency and isolates a failure", async () => {
  let active = 0, peak = 0;
  const started: number[] = [], finished: number[] = [];
  const release: (() => void)[] = [];
  const batch = runHealthBatch([1, 2, 3, 4, 5], async (item) => {
    started.push(item);
    peak = Math.max(peak, ++active);
    await new Promise<void>((resolve) => release.push(resolve));
    active--;
    finished.push(item);
    if (item === 2) throw new Error("one athlete failed");
  }, { concurrency: 2, startBefore: 100, clock: () => 0 });
  assert(started.join() === "1,2");
  for (let index = 0; index < 5; index++) {
    release[index]();
    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();
  }
  const result = await batch;
  assert(peak === 2 && started.join() === "1,2,3,4,5");
  assert(
    finished.length === 5 && result.failures.length === 1 &&
      result.deferred === 0,
  );
});
Deno.test("scheduler defers unstarted athletes at invocation deadline", async () => {
  let now = 0;
  const started: number[] = [];
  const result = await runHealthBatch([1, 2, 3, 4, 5], async (item) => {
    started.push(item);
    now = 100;
  }, { concurrency: 2, startBefore: 50, clock: () => now });
  assert(started.join() === "1" && result.deferred === 4);
});
Deno.test("provider pacing waits at least400ms and Retry-After supports seconds, dates and absent headers", async () => {
  let now = 0;
  const times: number[] = [], previous = globalThis.fetch;
  globalThis.fetch = () => {
    times.push(now);
    return Promise.resolve(new Response("{}"));
  };
  try {
    const budget = new HealthSyncBudget(25000, () => now, async (delay) => {
      now += delay;
    });
    await budget.fetch("https://health.googleapis.com/one");
    await budget.fetch("https://health.googleapis.com/two");
    await budget.fetch("https://health.googleapis.com/three");
    assert(times.join() === "0,400,800");
    assert(retryAfterTime("30", 1000) === 31000);
    assert(retryAfterTime(null, 1000) === 61000);
    assert(retryAfterTime(new Date(90000).toUTCString(), 1000) === 90000);
  } finally {
    globalThis.fetch = previous;
  }
});
function point(index: number) {
  return {
    dataPointName: `users/123456/dataTypes/exercise/dataPoints/run${index}`,
    exercise: {
      exerciseType: "RUNNING",
      interval: {
        startTime: "2026-10-25T00:30:00Z",
        endTime: "2026-10-25T01:30:00Z",
      },
      activeDuration: "3600s",
      metricsSummary: { distanceMillimeters: 10000000 },
    },
  };
}
async function checkResumableInterrupt(
  rateLimited: boolean,
  changedPage = false,
) {
  const previousFetch = globalThis.fetch;
  const previousKey = Deno.env.get("HEALTH_TOKEN_ENCRYPTION_KEY");
  const key = base64(crypto.getRandomValues(new Uint8Array(32)));
  Deno.env.set("HEALTH_TOKEN_ENCRYPTION_KEY", key);
  const connection = {
    id: "fixture-resume",
    user_id: "fixture-runner",
    provider_user_id: "123456",
    sync_cursor: {} as Record<string, unknown>,
  };
  const credentials = {
    expires_at: new Date(Date.now() + 3600000).toISOString(),
    access_token_ciphertext: await encrypt(
      "fixture-only-access",
      key,
      connection.id,
    ),
  };
  const upserts: string[] = [],
    fetched: string[] = [],
    statusWrites: Record<string, unknown>[] = [];
  let deleted = 0, now = 0, throttled = false;
  const client = {
    rpc: (name: string, args: Record<string, unknown>) => {
      if (name === "upsert_health_activity") {
        upserts.push(
          String(
            (args.p_activity as Record<string, unknown>).provider_workout_id,
          ),
        );
      }
      if (name === "reconcile_health_deletions") deleted++;
      return Promise.resolve({
        data: name === "health_consent_active"
          ? true
          : name === "claim_health_sync"
          ? "fixture-job"
          : name === "health_credentials_get"
          ? credentials
          : null,
        error: null,
      });
    },
    from: (table: string) => ({
      update: (value: Record<string, unknown>) => {
        if (table === "health_connections") {
          statusWrites.push(value);
          connection.sync_cursor = value.sync_cursor as Record<string, unknown>;
        }
        const q = {
          eq: () => q,
          in: () => q,
          is: () => q,
          lte: () => q,
          select: () => q,
          maybeSingle: () =>
            Promise.resolve({ data: { id: connection.id }, error: null }),
          then: (resolve: (value: unknown) => unknown) =>
            Promise.resolve({ data: null, error: null }).then(resolve),
        };
        return q;
      },
    }),
  } as unknown as SupabaseClient;
  globalThis.fetch = (input) => {
    const url = String(input);
    if (url.endsWith("/identity")) {
      now += 1000;
      return Promise.resolve(new Response('{"healthUserId":"123456"}'));
    }
    if (url.includes("dataPoints:reconcile")) {
      now += 1000;
      return Promise.resolve(
        new Response(
          JSON.stringify({
            dataPoints: [
              ...(changedPage && statusWrites.length > 0 ? [point(6)] : []),
              ...Array.from({ length: 6 }, (_, i) => point(i)),
            ],
          }),
        ),
      );
    }
    now += 4000;
    fetched.push(url);
    if (rateLimited && !throttled && url.endsWith("run2")) {
      throttled = true;
      return Promise.resolve(
        new Response("{}", { status: 429, headers: { "retry-after": "30" } }),
      );
    }
    return Promise.resolve(
      new Response(JSON.stringify(point(Number(url.match(/run(\d+)$/)?.[1])))),
    );
  };
  try {
    const budget = () =>
      new HealthSyncBudget(now + 25000, () => now, async (delay) => {
        now += delay;
      });
    const first = await syncConnection(
      client,
      connection,
      true,
      undefined,
      budget(),
    );
    const storedBeforeResume = rateLimited ? 2 : 4;
    assert(!first.complete && first.imported === storedBeforeResume);
    assert(
      connection.sync_cursor.pending_page === "" &&
        connection.sync_cursor.pending_item_offset === storedBeforeResume,
    );
    if (rateLimited) {
      assert(Date.parse(String(connection.sync_cursor.retry_at)) > Date.now());
    }
    assert(deleted === 0 && !("last_successful_sync_at" in statusWrites[0]));
    if (changedPage) {
      let complete = false;
      for (let attempt = 0; attempt < 4 && !complete; attempt++) {
        const result = await syncConnection(
          client,
          connection,
          true,
          undefined,
          budget(),
        );
        complete = result.complete;
        if (!complete) assert(deleted === 0);
      }
      assert(complete && new Set(upserts).size === 7 && Number(deleted) === 1);
      assert(fetched.some((url) => url.endsWith("run6")));
      return;
    }
    const before = fetched.length;
    const second = await syncConnection(
      client,
      connection,
      true,
      undefined,
      budget(),
    );
    assert(second.complete && second.imported === 6 - storedBeforeResume);
    assert(
      fetched.slice(before).every((url) =>
        Number(url.match(/run(\d+)$/)?.[1]) >= storedBeforeResume
      ),
    );
    assert(upserts.length === 6 && new Set(upserts).size === 6);
    assert(
      Number(deleted) === 1 &&
        typeof statusWrites[1].last_successful_sync_at === "string",
    );
    assert(!("pending_item_offset" in connection.sync_cursor));
  } finally {
    globalThis.fetch = previousFetch;
    if (previousKey === undefined) {
      Deno.env.delete("HEALTH_TOKEN_ENCRYPTION_KEY");
    } else Deno.env.set("HEALTH_TOKEN_ENCRYPTION_KEY", previousKey);
  }
}
Deno.test("mid-page budget checkpoints resume at next durable item, never advance success or delete early", () =>
  checkResumableInterrupt(false));
Deno.test("429 checkpoints the unprocessed item and Retry-After without false sync success", () =>
  checkResumableInterrupt(true));

Deno.test("a changed paused page replays idempotently instead of skipping shifted workouts", () =>
  checkResumableInterrupt(false, true));
