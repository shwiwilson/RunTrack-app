import type { SupabaseClient } from "npm:@supabase/supabase-js@2.119.0";
import {
  accessToken,
  HttpError,
  providerJson,
} from "../_shared/health_runtime.ts";
import { base64, encrypt } from "../_shared/health_core.ts";
function assert(value: unknown): asserts value {
  if (!value) throw new Error("Assertion failed");
}
Deno.test("unlinked identity provider response remains an honest reconnect error", async () => {
  const previous = globalThis.fetch;
  globalThis.fetch = () =>
    Promise.resolve(
      new Response(
        JSON.stringify({
          error: { details: [{ reason: "ACCOUNT_NOT_LINKED" }] },
        }),
        { status: 400 },
      ),
    );
  try {
    await providerJson(
      "https://health.googleapis.com/v4/users/me/identity",
      "test-only",
    );
    throw new Error("Expected failure");
  } catch (error) {
    assert(error instanceof HttpError && error.status === 409);
  } finally {
    globalThis.fetch = previous;
  }
});
Deno.test("expired refresh grant removes credentials and records revocation without sync success", async () => {
  const key = base64(crypto.getRandomValues(new Uint8Array(32)));
  Deno.env.set("HEALTH_TOKEN_ENCRYPTION_KEY", key);
  const connection = "fixture-connection";
  let deleted = false, revoked = false;
  const credentials = {
    expires_at: "2020-01-01T00:00:00Z",
    refresh_token_ciphertext: await encrypt("fixture-refresh", key, connection),
  };
  const fakeClient = {
    rpc: (name: string, args: Record<string, unknown>) => {
      if (name === "withdraw_health_consent") {
        deleted = true;
        revoked = args.p_reason === "provider_revoked" &&
          args.p_user_id === "fixture-user";
      }
      return Promise.resolve({
        data: name === "health_credentials_get" ? credentials : null,
        error: null,
      });
    },
    from: () => ({
      select: () => ({
        eq: () => ({
          single: () =>
            Promise.resolve({ data: { user_id: "fixture-user" }, error: null }),
        }),
      }),
    }),
  } as unknown as SupabaseClient;
  const previous = globalThis.fetch;
  globalThis.fetch = () =>
    Promise.resolve(new Response('{"error":"invalid_grant"}', { status: 400 }));
  try {
    await accessToken(fakeClient, connection);
    throw new Error("Expected failure");
  } catch (error) {
    assert(error instanceof HttpError && error.status === 401);
    assert(deleted && revoked);
  } finally {
    globalThis.fetch = previous;
    Deno.env.delete("HEALTH_TOKEN_ENCRYPTION_KEY");
  }
});

Deno.test("concurrent sync cannot claim an existing live lease", async () => {
  const { syncConnection } = await import("../_shared/health_runtime.ts");
  const fakeClient = {
    rpc: (name: string) =>
      Promise.resolve({
        data: name === "health_consent_active" ? true : null,
        error: null,
      }),
  } as unknown as SupabaseClient;
  try {
    await syncConnection(fakeClient, { id: "fixture" });
    throw new Error("Expected failure");
  } catch (error) {
    assert(error instanceof HttpError && error.status === 409);
  }
});
Deno.test("revocation during sync cannot be reported as a successful connected state", async () => {
  const { syncConnection } = await import("../_shared/health_runtime.ts");
  const connection = "fixture-cancelled",
    key = base64(crypto.getRandomValues(new Uint8Array(32)));
  Deno.env.set("HEALTH_TOKEN_ENCRYPTION_KEY", key);
  const credentials = {
    expires_at: new Date(Date.now() + 3600000).toISOString(),
    access_token_ciphertext: await encrypt("test-only-access", key, connection),
  };
  let guardedStatusUpdate = false, failedJob = false;
  const fakeClient = {
    rpc: (name: string) =>
      Promise.resolve({
        data: name === "health_consent_active"
          ? true
          : name === "claim_health_sync"
          ? "test-job"
          : name === "health_credentials_get"
          ? credentials
          : null,
        error: null,
      }),
    from: (table: string) => ({
      update: (value: Record<string, unknown>) => {
        if (table === "sync_jobs") {
          failedJob ||= value.status === "failed";
          return { eq: () => Promise.resolve({ data: null, error: null }) };
        }
        return {
          eq: () => ({
            eq: () => ({
              in: (_column: string, statuses: string[]) => {
                guardedStatusUpdate = statuses.includes("connected") &&
                  !statuses.includes("disconnected");
                return {
                  select: () => ({
                    maybeSingle: () =>
                      Promise.resolve({ data: null, error: null }),
                  }),
                };
              },
            }),
          }),
        };
      },
    }),
  } as unknown as SupabaseClient;
  const previous = globalThis.fetch;
  globalThis.fetch = (input) =>
    Promise.resolve(
      new Response(JSON.stringify(
        String(input).endsWith("/identity")
          ? { healthUserId: "fixture-health-id" }
          : { dataPoints: [] },
      )),
    );
  try {
    await syncConnection(fakeClient, {
      id: connection,
      user_id: "fixture-user",
      provider_user_id: "fixture-health-id",
      sync_cursor: {},
    }, true);
    throw new Error("Expected cancellation");
  } catch (error) {
    assert(error instanceof HttpError && error.status === 409);
    assert(guardedStatusUpdate && failedJob);
  } finally {
    globalThis.fetch = previous;
    Deno.env.delete("HEALTH_TOKEN_ENCRYPTION_KEY");
  }
});
