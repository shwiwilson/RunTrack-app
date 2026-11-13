import { sha256 } from "./health_core.ts";
import { HttpError } from "./health_runtime.ts";

export type HealthNotification = {
  provider_event_id: string;
  health_user_id: string;
  event_type: string;
  payload: Record<string, unknown>;
};

// Signatures cover the raw request, but delivery identity must not depend on JSON
// object member order. Preserve all event values, including timestamps, so later
// real notifications for the same workout still receive distinct identities.
function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (value !== null && typeof value === "object") {
    const object = value as Record<string, unknown>;
    return `{${
      Object.keys(object).sort().map((key) =>
        `${JSON.stringify(key)}:${canonicalJson(object[key])}`
      ).join(",")
    }}`;
  }
  return JSON.stringify(value) ?? "null";
}

export async function normaliseHealthNotifications(
  payload: unknown,
): Promise<HealthNotification[]> {
  const items = Array.isArray(payload) ? payload : [payload];
  if (items.length > 99) {
    throw new HttpError(400, "Notification batch too large");
  }
  const events = await Promise.all(items.map(async (item) => {
    const data = item?.data;
    if (
      !data || typeof data.healthUserId !== "string" ||
      data.healthUserId.length < 1 || data.healthUserId.length > 1024 ||
      typeof data.dataType !== "string"
    ) throw new HttpError(400, "Malformed notification");
    if (
      !["exercise", "user-deleted", "user-revoked-access"].includes(
        data.dataType,
      )
    ) return null;
    return {
      provider_event_id: await sha256(canonicalJson(item)),
      health_user_id: data.healthUserId,
      event_type: data.dataType,
      payload: {
        operation: data.operation ?? null,
        record_id: data.recordId ?? null,
        intervals: Array.isArray(data.intervals) ? data.intervals : [],
      },
    };
  }));
  return events.filter((event): event is NonNullable<typeof event> =>
    event !== null
  );
}
