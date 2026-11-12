// Provider adapter: no HTTP, environment access, database access or generated measurements.
export const GOOGLE_HEALTH_SCOPE =
  "https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly";
export const GOOGLE_HEALTH_API = "https://health.googleapis.com/v4";
const utf8 = new TextEncoder();
export const base64 = (bytes: Uint8Array): string =>
  btoa(String.fromCharCode(...bytes));
export const unbase64 = (value: string): Uint8Array<ArrayBuffer> =>
  Uint8Array.from(atob(value), (c) => c.charCodeAt(0));
export const base64url = (bytes: Uint8Array): string =>
  base64(bytes).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
export const randomSecret = (): string =>
  base64url(crypto.getRandomValues(new Uint8Array(32)));
export async function sha256(value: string): Promise<string> {
  return base64url(
    new Uint8Array(await crypto.subtle.digest("SHA-256", utf8.encode(value))),
  );
}
export function constantTimeEqual(a: string, b: string): boolean {
  const x = utf8.encode(a), y = utf8.encode(b);
  let difference = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    difference |= (x[i] ?? 0) ^ (y[i] ?? 0);
  }
  return difference === 0;
}
export async function encrypt(
  value: string,
  keyBase64: string,
  context: string,
): Promise<string> {
  const rawKey = unbase64(keyBase64);
  if (rawKey.length !== 32) {
    throw new Error("HEALTH_TOKEN_ENCRYPTION_KEY must encode 32 random bytes");
  }
  const key = await crypto.subtle.importKey("raw", rawKey, "AES-GCM", false, [
    "encrypt",
  ]);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv, additionalData: utf8.encode(context) },
    key,
    utf8.encode(value),
  );
  return `v1.${base64(iv)}.${base64(new Uint8Array(ciphertext))}`;
}
export async function decrypt(
  value: string,
  keyBase64: string,
  context: string,
): Promise<string> {
  const [version, iv, ciphertext] = value.split(".");
  if (version !== "v1" || !iv || !ciphertext) {
    throw new Error("Invalid encrypted credential");
  }
  const key = await crypto.subtle.importKey(
    "raw",
    unbase64(keyBase64),
    "AES-GCM",
    false,
    ["decrypt"],
  );
  const plaintext = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: unbase64(iv), additionalData: utf8.encode(context) },
    key,
    unbase64(ciphertext),
  );
  return new TextDecoder().decode(plaintext);
}
export function linkedHealthIdentity(
  identity: Record<string, unknown>,
): string {
  if (
    typeof identity.healthUserId !== "string" ||
    !/^[a-zA-Z0-9-]{1,63}$/.test(identity.healthUserId)
  ) {
    throw new Error(
      "Google Account is not linked to Google Health. Open the Google Health app first.",
    );
  }
  return identity.healthUserId;
}
export function needsTokenRefresh(
  expiresAt: string,
  now = Date.now(),
): boolean {
  const expiry = Date.parse(expiresAt);
  return !Number.isFinite(expiry) || expiry <= now + 60_000;
}
const object = (value: unknown): Record<string, unknown> =>
  value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
const nonnegative = (value: unknown): number | null => {
  if (value === null || value === undefined || value === "") return null;
  const result = Number(value);
  return Number.isFinite(result) && result >= 0 ? result : null;
};
export function seconds(value: unknown): number | null {
  if (typeof value !== "string" || !/^\d+(\.\d{1,9})?s$/.test(value)) {
    return null;
  }
  return nonnegative(value.slice(0, -1));
}
function utcOffset(value: unknown): string | null {
  if (typeof value !== "string" || !/^-?\d+s$/.test(value)) return null;
  const seconds = Number(value.slice(0, -1));
  if (Math.abs(seconds) > 86400) return null;
  const minutes = Math.floor(Math.abs(seconds) / 60);
  return `UTC${seconds < 0 ? "-" : "+"}${
    String(Math.floor(minutes / 60)).padStart(2, "0")
  }:${String(minutes % 60).padStart(2, "0")}`;
}
export function normaliseGoogleWorkout(
  point: Record<string, unknown>,
  userId: string,
) {
  const exercise = object(point.exercise),
    interval = object(exercise.interval),
    metrics = object(exercise.metricsSummary);
  if (
    !["RUNNING", "TRAIL_RUN", "TREADMILL"].includes(
      String(exercise.exerciseType),
    )
  ) return null;
  const name = String(point.name ?? point.dataPointName ?? "");
  if (
    !/^users\/[a-zA-Z0-9-]+\/dataTypes\/exercise\/dataPoints\/[a-zA-Z0-9_-]+$/
      .test(name)
  ) throw new Error("Workout has no stable provider identifier");
  const start = Date.parse(String(interval.startTime)),
    end = Date.parse(String(interval.endTime));
  if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) {
    throw new Error("Workout timestamps are invalid");
  }
  const elapsed = (end - start) / 1000,
    active = seconds(exercise.activeDuration);
  if (active !== null && active > elapsed) {
    throw new Error("Active duration exceeds elapsed duration");
  }
  const source = object(point.dataSource);
  const activity = {
    user_id: userId,
    provider: "google_health",
    provider_workout_id: name,
    type: "running",
    title: typeof exercise.displayName === "string"
      ? exercise.displayName
      : "Run",
    started_at: new Date(start).toISOString(),
    ended_at: new Date(end).toISOString(),
    time_zone: utcOffset(interval.startUtcOffset),
    distance_m: metrics.distanceMillimeters == null
      ? null
      : nonnegative(metrics.distanceMillimeters) === null
      ? null
      : Number(metrics.distanceMillimeters) / 1000,
    active_duration_s: active,
    elapsed_duration_s: elapsed,
    average_heart_rate:
      nonnegative(metrics.averageHeartRateBeatsPerMinute) !== null &&
        Number(metrics.averageHeartRateBeatsPerMinute) > 0 &&
        Number(metrics.averageHeartRateBeatsPerMinute) < 300
        ? Number(metrics.averageHeartRateBeatsPerMinute)
        : null,
    maximum_heart_rate: null,
    calories_kcal: nonnegative(metrics.caloriesKcal),
    elevation_gain_m: metrics.elevationGainMillimeters == null
      ? null
      : nonnegative(metrics.elevationGainMillimeters) === null
      ? null
      : Number(metrics.elevationGainMillimeters) / 1000,
    device_info: object(source.device),
    sync_status: "synced",
    // Deliberately excludes routes, coordinates, tokens and the raw provider payload.
    provenance: {
      provider: "google_health",
      exercise_type: exercise.exerciseType,
      resource_name: name,
      recording_method: source.recordingMethod ?? null,
      platform: source.platform ?? null,
      application: object(source.application),
      provider_updated_at: exercise.updateTime ?? null,
      start_utc_offset: interval.startUtcOffset ?? null,
      end_utc_offset: interval.endUtcOffset ?? null,
      reconciled: point.dataPointName != null,
    },
  };
  const splits = Array.isArray(exercise.splitSummaries)
    ? exercise.splitSummaries
    : [];
  const laps = splits.map((raw, index) => {
    const split = object(raw), summary = object(split.metricsSummary);
    return {
      lap_index: index + 1,
      started_at: split.startTime ?? null,
      ended_at: split.endTime ?? null,
      distance_m: summary.distanceMillimeters == null
        ? null
        : nonnegative(summary.distanceMillimeters) === null
        ? null
        : Number(summary.distanceMillimeters) / 1000,
      active_duration_s: seconds(split.activeDuration),
    };
  });
  return { activity, laps };
}
// Only explicit source identity proves a duplicate. Similar distance/time alone never deletes a run.
export function sameOrigin(
  a: Record<string, unknown>,
  b: Record<string, unknown>,
): boolean {
  const x = object(a.provenance), y = object(b.provenance);
  return a.user_id === b.user_id && typeof x.origin_workout_id === "string" &&
    x.origin_workout_id.length > 0 &&
    x.origin_provider === y.origin_provider &&
    x.origin_workout_id === y.origin_workout_id;
}

// Google documents Tink ECDSA-P256-SHA256 signatures with a five-byte key prefix.
// WebCrypto consumes IEEE-P1363 signatures, so convert DER integers to fixed-width r||s.
export function derToP1363(signature: Uint8Array): Uint8Array<ArrayBuffer> {
  if (
    signature[0] !== 0x30 || signature[1] !== signature.length - 2 ||
    signature[2] !== 0x02
  ) throw new Error("Invalid DER signature");
  const rLength = signature[3], sTag = 4 + rLength;
  if (signature[sTag] !== 0x02) throw new Error("Invalid DER signature");
  const sLength = signature[sTag + 1];
  if (sTag + 2 + sLength !== signature.length) {
    throw new Error("Invalid DER signature");
  }
  const result = new Uint8Array(64);
  for (
    const [part, offset] of [[signature.slice(4, 4 + rLength), 0], [
      signature.slice(sTag + 2),
      32,
    ]] as const
  ) {
    const bytes = part.length === 33 && part[0] === 0 ? part.slice(1) : part;
    if (bytes.length < 1 || bytes.length > 32) {
      throw new Error("Invalid ECDSA integer");
    }
    result.set(bytes, offset + 32 - bytes.length);
  }
  return result;
}
function protoFields(bytes: Uint8Array): Map<number, Uint8Array> {
  let offset = 0;
  const fields = new Map<number, Uint8Array>();
  const varint = () => {
    let result = 0, shift = 0;
    while (offset < bytes.length && shift <= 28) {
      const value = bytes[offset++];
      result |= (value & 127) << shift;
      if (!(value & 128)) return result;
      shift += 7;
    }
    throw new Error("Invalid protobuf");
  };
  while (offset < bytes.length) {
    const tag = varint(), wire = tag & 7;
    if (wire === 0) {
      varint();
      continue;
    }
    if (wire !== 2) throw new Error("Unsupported protobuf field");
    const length = varint();
    if (length < 0 || offset + length > bytes.length) {
      throw new Error("Invalid protobuf length");
    }
    fields.set(tag >> 3, bytes.slice(offset, offset + length));
    offset += length;
  }
  return fields;
}
export async function verifyWebhookSignature(
  raw: string,
  signatureBase64: string,
  keyset: Record<string, unknown>,
): Promise<boolean> {
  try {
    const signature = unbase64(signatureBase64);
    if (signature.length < 8 || signature[0] !== 1) return false;
    const keyId = new DataView(
      signature.buffer,
      signature.byteOffset,
      signature.byteLength,
    ).getUint32(1);
    const keys = Array.isArray(keyset.key) ? keyset.key : [];
    const found = keys.map(object).find((key) =>
      key.keyId === keyId && key.status === "ENABLED" &&
      key.outputPrefixType === "TINK"
    );
    const keyData = object(found?.keyData);
    if (
      !String(keyData.typeUrl).endsWith("/google.crypto.tink.EcdsaPublicKey") ||
      typeof keyData.value !== "string"
    ) return false;
    const fields = protoFields(unbase64(keyData.value));
    const coordinate = (value: Uint8Array | undefined) => {
      if (!value) return null;
      const bytes = value.length === 33 && value[0] === 0
        ? value.slice(1)
        : value;
      if (bytes.length > 32 || bytes.length === 0) return null;
      const padded = new Uint8Array(32);
      padded.set(bytes, 32 - bytes.length);
      return padded;
    };
    const x = coordinate(fields.get(3)), y = coordinate(fields.get(4));
    if (!x || !y) return false;
    const key = await crypto.subtle.importKey(
      "jwk",
      { kty: "EC", crv: "P-256", x: base64url(x), y: base64url(y), ext: true },
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["verify"],
    );
    return await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      derToP1363(signature.slice(5)),
      utf8.encode(raw),
    );
  } catch {
    return false;
  }
}
