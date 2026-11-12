import { normaliseHealthNotifications } from "../_shared/health_webhook.ts";
import { HttpError } from "../_shared/health_runtime.ts";
function assert(value: unknown): asserts value {
  if (!value) throw new Error("Assertion failed");
}
Deno.test("signed notification normalization preserves only required queue metadata", async () => {
  const item = {
    data: {
      healthUserId: "provider-user",
      dataType: "exercise",
      operation: "UPDATED",
      recordId: "record-one",
      intervals: [{ start: "2026-11-01T00:00:00Z" }],
      user_id: "spoofed",
      connection_id: "spoofed",
    },
    unexpected: "not persisted",
  };
  const [event] = await normaliseHealthNotifications(item);
  assert(
    event.health_user_id === "provider-user" && event.event_type === "exercise",
  );
  assert(/^[A-Za-z0-9_-]{43}$/.test(event.provider_event_id));
  assert(
    event.payload.record_id === "record-one" && !("user_id" in event) &&
      !("connection_id" in event),
  );
  assert(!("unexpected" in event.payload));
  const [replay] = await normaliseHealthNotifications(item);
  assert(replay.provider_event_id === event.provider_event_id);
});
Deno.test("notification batches are bounded before hashing and preserve revocations", async () => {
  const item = {
    data: { healthUserId: "provider-user", dataType: "exercise" },
  };
  const batch = await normaliseHealthNotifications(Array(99).fill(item));
  assert(batch.length === 99);
  for (
    const payload of [Array(100).fill(item), null, {}, {
      data: { healthUserId: "", dataType: "exercise" },
    }]
  ) {
    try {
      await normaliseHealthNotifications(payload);
      throw new Error("Expected rejection");
    } catch (error) {
      assert(error instanceof HttpError && error.status === 400);
    }
  }
  const revoked = await normaliseHealthNotifications([
    {
      data: { healthUserId: "provider-user", dataType: "user-revoked-access" },
    },
    { data: { healthUserId: "provider-user", dataType: "user-deleted" } },
    { data: { healthUserId: "provider-user", dataType: "unrequested" } },
  ]);
  assert(
    revoked.length === 2 && revoked[0].event_type === "user-revoked-access" &&
      revoked[1].event_type === "user-deleted",
  );
});
