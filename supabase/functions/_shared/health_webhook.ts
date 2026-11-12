import { sha256 } from "./health_core.ts";
import { HttpError } from "./health_runtime.ts";

export type HealthNotification = {
  provider_event_id: string;
  health_user_id: string;
  event_type: string;
  payload: Record<string, unknown>;
};

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
      provider_event_id: await sha256(JSON.stringify(item)),
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
