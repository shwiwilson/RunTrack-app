import {
  base64,
  constantTimeEqual,
  decrypt,
  derToP1363,
  encrypt,
  GOOGLE_HEALTH_SCOPE,
  linkedHealthIdentity,
  needsTokenRefresh,
  normaliseGoogleWorkout,
  randomSecret,
  sameOrigin,
  sha256,
  verifyWebhookSignature,
} from "../_shared/health_core.ts";
function assert(
  condition: unknown,
  message = "Assertion failed",
): asserts condition {
  if (!condition) throw new Error(message);
}
async function rejects(action: () => unknown | Promise<unknown>) {
  let rejected = false;
  try {
    await action();
  } catch {
    rejected = true;
  }
  assert(rejected, "Expected rejection");
}
const user = "11111111-1111-4111-8111-111111111111";
function point(overrides: Record<string, unknown> = {}) {
  return {
    dataPointName: "users/123456/dataTypes/exercise/dataPoints/abc123",
    exercise: {
      exerciseType: "RUNNING",
      interval: {
        startTime: "2026-10-25T00:30:00Z",
        endTime: "2026-10-25T01:40:00Z",
        startUtcOffset: "3600s",
        endUtcOffset: "0s",
      },
      activeDuration: "3600s",
      metricsSummary: { distanceMillimeters: 10000000 },
      ...overrides,
    },
  };
}
Deno.test("provider normalisation uses active time, real UTC intervals, millimetres and nullable measurements", () => {
  const result = normaliseGoogleWorkout(point(), user)!;
  assert(result.activity.distance_m === 10000);
  assert(result.activity.active_duration_s === 3600);
  assert(result.activity.elapsed_duration_s === 4200);
  assert(result.activity.average_heart_rate === null);
  assert(result.activity.maximum_heart_rate === null);
  assert(result.activity.calories_kcal === null);
  assert(result.activity.provenance.end_utc_offset === "0s");
  assert(!("route" in result.activity));
});
Deno.test("empty, zero and malformed measurements do not become invented distance", () => {
  assert(
    normaliseGoogleWorkout(point({ metricsSummary: {} }), user)!.activity
      .distance_m === null,
  );
  assert(
    normaliseGoogleWorkout(
      point({
        metricsSummary: { distanceMillimeters: 0 },
        activeDuration: "0s",
      }),
      user,
    )!.activity.distance_m === 0,
  );
  assert(
    normaliseGoogleWorkout(
      point({ metricsSummary: { distanceMillimeters: "invalid" } }),
      user,
    )!.activity.distance_m === null,
  );
});
Deno.test("invalid source identities, reversed timestamps and impossible paused durations reject", async () => {
  await rejects(() =>
    normaliseGoogleWorkout(
      { ...point(), dataPointName: "../../someone-else" },
      user,
    )
  );
  await rejects(() =>
    normaliseGoogleWorkout(
      point({
        interval: {
          startTime: "2026-10-25T01:40:00Z",
          endTime: "2026-10-25T00:30:00Z",
        },
      }),
      user,
    )
  );
  await rejects(() =>
    normaliseGoogleWorkout(point({ activeDuration: "4202s" }), user)
  );
  assert(
    normaliseGoogleWorkout(point({ exerciseType: "WALKING" }), user) === null,
  );
});
Deno.test("documented trail and treadmill running types are included; invalid heart rates stay unavailable", () => {
  assert(
    normaliseGoogleWorkout(point({ exerciseType: "TRAIL_RUN" }), user) !== null,
  );
  assert(
    normaliseGoogleWorkout(point({ exerciseType: "TREADMILL" }), user) !== null,
  );
  assert(
    normaliseGoogleWorkout(point({ exerciseType: "TREADMILL_WALK" }), user) ===
      null,
  );
  assert(
    normaliseGoogleWorkout(
      point({ metricsSummary: { averageHeartRateBeatsPerMinute: "0" } }),
      user,
    )!.activity.average_heart_rate === null,
  );
});
Deno.test("Google login alone cannot satisfy linked Google Health identity", async () => {
  await rejects(() =>
    linkedHealthIdentity({ sub: "google-user", email: "runner@example.test" })
  );
  assert(linkedHealthIdentity({ healthUserId: "123456789" }) === "123456789");
  assert(GOOGLE_HEALTH_SCOPE.endsWith("activity_and_fitness.readonly"));
  assert(!GOOGLE_HEALTH_SCOPE.includes("location"));
});
Deno.test("cryptographic state tokens and encrypted credentials detect tampering and wrong owner context", async () => {
  const secret = randomSecret(), other = randomSecret();
  assert(secret.length === 43 && secret !== other);
  assert(await sha256(secret) !== await sha256(other));
  const key = base64(crypto.getRandomValues(new Uint8Array(32))),
    encrypted = await encrypt("private-refresh-token", key, user);
  assert(!encrypted.includes("private-refresh-token"));
  assert(await decrypt(encrypted, key, user) === "private-refresh-token");
  await rejects(() => decrypt(encrypted, key, "another-connection"));
  await rejects(() => decrypt(encrypted.slice(0, -3) + "xyz", key, user));
  assert(constantTimeEqual("same", "same"));
  assert(!constantTimeEqual("same", "same!"));
});
Deno.test("expired access tokens refresh before expiry; invalid expiry cannot be treated as valid", () => {
  const now = Date.parse("2026-11-12T12:00:00Z");
  assert(needsTokenRefresh("2026-11-12T11:59:59Z", now));
  assert(needsTokenRefresh("2026-11-12T12:00:59Z", now));
  assert(!needsTokenRefresh("2026-11-12T13:00:00Z", now));
  assert(needsTokenRefresh("invalid", now));
});
Deno.test("cross-provider duplication requires an explicit shared source identity", () => {
  const a = {
    user_id: user,
    distance_m: 5000,
    provenance: { origin_provider: "watch", origin_workout_id: "original-1" },
  };
  assert(
    !sameOrigin(a, {
      ...a,
      provenance: { origin_provider: "watch", origin_workout_id: "original-2" },
    }),
  );
  assert(!sameOrigin(a, { ...a, user_id: "other" }));
  assert(sameOrigin(a, { ...a, provider: "other-provider" }));
  assert(
    !sameOrigin({ user_id: user, distance_m: 5000 }, {
      user_id: user,
      distance_m: 5000,
    }),
  );
});
function toDer(raw: Uint8Array): Uint8Array {
  const integer = (part: Uint8Array) => {
    let offset = 0;
    while (offset < 31 && part[offset] === 0) offset++;
    const bytes = part.slice(offset);
    return bytes[0] & 128 ? new Uint8Array([0, ...bytes]) : bytes;
  };
  const r = integer(raw.slice(0, 32)), s = integer(raw.slice(32));
  return new Uint8Array([
    0x30,
    4 + r.length + s.length,
    2,
    r.length,
    ...r,
    2,
    s.length,
    ...s,
  ]);
}
Deno.test("webhook verifies authentic Tink prefix/signature and rejects spoofing, body tampering and unknown keys", async () => {
  const keys = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const publicJwk = await crypto.subtle.exportKey("jwk", keys.publicKey);
  const decode = (s: string) =>
    Uint8Array.from(
      atob(s.replaceAll("-", "+").replaceAll("_", "/")),
      (c) => c.charCodeAt(0),
    );
  const protobuf = new Uint8Array([
    26,
    33,
    0,
    ...decode(publicJwk.x!),
    34,
    33,
    0,
    ...decode(publicJwk.y!),
  ]);
  const keyset = {
    key: [{
      keyId: 42,
      status: "ENABLED",
      outputPrefixType: "TINK",
      keyData: {
        typeUrl: "type.googleapis.com/google.crypto.tink.EcdsaPublicKey",
        value: base64(protobuf),
      },
    }],
  };
  const body = '{"data":{"healthUserId":"123","dataType":"exercise"}}';
  const rawSignature = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      keys.privateKey,
      new TextEncoder().encode(body),
    ),
  );
  const der = toDer(rawSignature);
  assert(derToP1363(der).every((v, i) => v === rawSignature[i]));
  const signature = base64(new Uint8Array([1, 0, 0, 0, 42, ...der]));
  assert(await verifyWebhookSignature(body, signature, keyset));
  assert(!await verifyWebhookSignature(body + " ", signature, keyset));
  assert(!await verifyWebhookSignature(body, "fabricated", keyset));
  assert(!await verifyWebhookSignature(body, signature, { key: [] }));
});
