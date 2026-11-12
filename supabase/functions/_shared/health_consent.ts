import { HttpError } from "./health_runtime.ts";

export const HEALTH_CONSENT_VERSION = "2026-11-12-v1";

export function validateHealthConsent(value: unknown): void {
  const consent = value as Record<string, unknown> | null;
  if (
    !consent || consent.health_data_consent !== true ||
    consent.consent_version !== HEALTH_CONSENT_VERSION
  ) {
    throw new HttpError(
      400,
      "Review and explicitly agree to the health data consent before connecting.",
    );
  }
}
