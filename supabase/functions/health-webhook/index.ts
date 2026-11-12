import {
  constantTimeEqual,
  sha256,
  verifyWebhookSignature,
} from "../_shared/health_core.ts";
import {
  check,
  env,
  HttpError,
  serviceClient,
} from "../_shared/health_runtime.ts";
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
    const payload = JSON.parse(raw);
    // The provider's mandatory authorized / unauthorized verification handshake.
    if (!Array.isArray(payload) && payload.type === "verification") {
      return new Response(null, { status: 200 });
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
    const items = Array.isArray(payload) ? payload : [payload];
    if (items.length > 99) return new Response(null, { status: 400 });
    const client = serviceClient();
    // Durable idempotent queue, kept lightweight. Scheduled reconciliation consumes it.
    for (const item of items) {
      const data = item?.data;
      if (
        !data || typeof data.healthUserId !== "string" ||
        typeof data.dataType !== "string"
      ) throw new HttpError(400, "Malformed notification");
      if (
        !["exercise", "user-deleted", "user-revoked-access"].includes(
          data.dataType,
        )
      ) continue;
      const connection = check(
        await client.from("health_connections").select("id").eq(
          "provider",
          "google_health",
        ).eq("provider_user_id", data.healthUserId).maybeSingle(),
      );
      if (!connection) continue;
      const inserted = check(
        await client.from("sync_events").upsert({
          provider: "google_health",
          provider_event_id: await sha256(JSON.stringify(item)),
          connection_id: connection.id,
          event_type: data.dataType,
          payload: {
            operation: data.operation ?? null,
            record_id: data.recordId ?? null,
            intervals: Array.isArray(data.intervals) ? data.intervals : [],
          },
        }, {
          onConflict: "provider,provider_event_id",
          ignoreDuplicates: true,
        }).select("id"),
      );
      if (!inserted?.length) continue;
      if (
        data.dataType === "user-deleted" ||
        data.dataType === "user-revoked-access"
      ) {
        check(
          await client.rpc("health_credentials_delete", {
            p_connection_id: connection.id,
          }),
        );
        check(
          await client.from("health_connections").update({
            status: "revoked",
            last_error:
              "Google Health access was revoked. Reconnect to sync again.",
          }).eq("id", connection.id),
        );
      }
    }
    return new Response(null, { status: 204 });
  } catch {
    return new Response(null, { status: 503 });
  }
});
