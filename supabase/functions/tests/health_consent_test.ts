import type { SupabaseClient } from "npm:@supabase/supabase-js@2.119.0";
import {
  HEALTH_CONSENT_VERSION,
  validateHealthConsent,
} from "../_shared/health_consent.ts";
import {
  HttpError,
  requireHealthConsent,
  syncConnection,
} from "../_shared/health_runtime.ts";
function assert(value: unknown): asserts value {
  if (!value) throw new Error("Assertion failed");
}
Deno.test("health consent requires an explicit true action and exact current text version", () => {
  for (
    const value of [
      null,
      {},
      { health_data_consent: "true", consent_version: HEALTH_CONSENT_VERSION },
      { health_data_consent: false, consent_version: HEALTH_CONSENT_VERSION },
      { health_data_consent: true },
      { health_data_consent: true, consent_version: "old" },
    ]
  ) {
    try {
      validateHealthConsent(value);
      throw new Error("Expected rejection");
    } catch (error) {
      assert(error instanceof HttpError && error.status === 400);
    }
  }
  validateHealthConsent({
    health_data_consent: true,
    consent_version: HEALTH_CONSENT_VERSION,
  });
});
Deno.test("OAuth callback consent check binds to the saved grant ID", async () => {
  let checked = false;
  const client = {
    rpc: (name: string, args: Record<string, unknown>) => {
      checked = name === "health_consent_active" &&
        args.p_user_id === "trusted-user" && args.p_consent_id === 42;
      return Promise.resolve({ data: true, error: null });
    },
  } as unknown as SupabaseClient;
  await requireHealthConsent(client, "trusted-user", 42);
  assert(checked);
});
Deno.test("withdrawn or absent consent stops sync before provider requests or job creation", async () => {
  let requests = 0, claims = 0;
  const client = {
    rpc: (name: string) => {
      if (name === "claim_health_sync") claims++;
      return Promise.resolve({ data: false, error: null });
    },
  } as unknown as SupabaseClient;
  const previous = globalThis.fetch;
  globalThis.fetch = () => {
    requests++;
    throw new Error("Provider should not be contacted");
  };
  try {
    await syncConnection(client, { id: "connection", user_id: "trusted-user" });
    throw new Error("Expected rejection");
  } catch (error) {
    assert(error instanceof HttpError && error.status === 403);
    assert(requests === 0 && claims === 0);
  } finally {
    globalThis.fetch = previous;
  }
});
