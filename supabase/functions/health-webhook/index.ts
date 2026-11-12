import {
  constantTimeEqual,
  verifyWebhookSignature,
} from "../_shared/health_core.ts";
import {
  check,
  env,
  HttpError,
  serviceClient,
} from "../_shared/health_runtime.ts";
import { normaliseHealthNotifications } from "../_shared/health_webhook.ts";
let keyset: Record<string, unknown> | undefined, keysFetchedAt = 0;
async function publicKeys(force = false) {
  if (!keyset || force || Date.now() - keysFetchedAt > 3600000) {
    const response = await fetch(
      "https://www.gstatic.com/googlehealthapi/webhooks/webhooks_public_keyset.json",
      { signal: AbortSignal.timeout(10000) },
    );
    if (!response.ok) throw new Error("Signing keys unavailable");
    keyset = await response.json();
    keysFetchedAt = Date.now();
  }
  return keyset!;
}
Deno.serve(async (request) => {
  try {
    if (request.method !== "POST") return new Response(null, { status: 405 });
    const secret = env("GOOGLE_HEALTH_WEBHOOK_SECRET");
    if (
      !secret ||
      !constantTimeEqual(
        request.headers.get("authorization") ?? "",
        `Bearer ${secret}`,
      )
    ) return new Response(null, { status: 401 });
    const contentLength = Number(request.headers.get("content-length") ?? 0);
    if (contentLength > 1048576) return new Response(null, { status: 413 });
    const raw = await request.text();
    if (raw.length > 1048576) return new Response(null, { status: 413 });
    let payload: unknown;
    try {
      payload = JSON.parse(raw);
    } catch {
      throw new HttpError(400, "Malformed notification");
    }
    // The provider's mandatory authorized / unauthorized verification handshake.
    if (
      payload && typeof payload === "object" && !Array.isArray(payload) &&
      (payload as Record<string, unknown>).type === "verification"
    ) {
      return new Response(null, { status: 201 });
    }
    const signature = request.headers.get("google-health-api-signature") ?? "";
    let verified = await verifyWebhookSignature(
      raw,
      signature,
      await publicKeys(),
    );
    if (!verified) {
      verified = await verifyWebhookSignature(
        raw,
        signature,
        await publicKeys(true),
      );
    }
    if (!verified) return new Response(null, { status: 401 });
    const events = await normaliseHealthNotifications(payload);
    const client = serviceClient();
    // One database round trip durably queues the complete batch and applies
    // revocations atomically. A failed transaction returns 503 for Google retry.
    check(
      await client.rpc("enqueue_health_notifications", { p_events: events }),
    );
    return new Response(null, { status: 204 });
  } catch (error) {
    return new Response(null, {
      status: error instanceof HttpError ? error.status : 503,
    });
  }
});
