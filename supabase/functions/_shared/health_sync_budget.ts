// Leave time for durable cursor/job writes before the hosted worker's limit.
export class SyncBudgetExceeded extends Error {}
export class HealthRateLimited extends Error {
  constructor(public retryAt: number) {
    super(
      "Google Health temporarily limited requests. Sync will resume later.",
    );
  }
}
export function retryAfterTime(value: string | null, now: number): number {
  const seconds = value === null || value.trim() === "" ? NaN : Number(value);
  const parsed = Number.isFinite(seconds)
    ? now + seconds * 1000
    : Date.parse(value ?? "");
  return Math.max(
    now + 1000,
    Math.min(now + 86400000, Number.isFinite(parsed) ? parsed : now + 60000),
  );
}
export class HealthSyncBudget {
  private nextRequestAt = 0;
  constructor(
    readonly deadline: number,
    private readonly clock: () => number = Date.now,
    private readonly sleep: (milliseconds: number) => Promise<void> = (
      milliseconds,
    ) => new Promise((resolve) => setTimeout(resolve, milliseconds)),
  ) {}
  remaining(): number {
    return this.deadline - this.clock();
  }
  database<T>(query: PromiseLike<T>): PromiseLike<T> {
    if (this.remaining() <= 0) throw new SyncBudgetExceeded();
    const abortable = query as PromiseLike<T> & {
      abortSignal?: (signal: AbortSignal) => PromiseLike<T>;
    };
    return typeof abortable.abortSignal === "function"
      ? abortable.abortSignal(
        AbortSignal.timeout(Math.max(1, Math.min(5000, this.remaining()))),
      )
      : query;
  }
  ensure(): void {
    if (this.remaining() <= 5000) throw new SyncBudgetExceeded();
  }
  async fetch(
    input: string,
    init: RequestInit = {},
    paced = true,
  ): Promise<Response> {
    this.ensure();
    if (paced) {
      const wait = Math.max(0, this.nextRequestAt - this.clock());
      if (wait >= this.remaining() - 5000) throw new SyncBudgetExceeded();
      if (wait) await this.sleep(wait);
      this.ensure();
      // Unverified Google Health applications are limited to 2.5 QPS per user.
      this.nextRequestAt = this.clock() + 400;
    }
    const timeout = Math.max(1, Math.min(8000, this.remaining() - 5000));
    try {
      return await fetch(input, {
        ...init,
        signal: AbortSignal.timeout(timeout),
      });
    } catch (error) {
      if (
        error instanceof DOMException &&
        (error.name === "TimeoutError" || error.name === "AbortError")
      ) {
        throw new SyncBudgetExceeded();
      }
      throw error;
    }
  }
}
export async function runHealthBatch<T>(
  items: T[],
  process: (item: T) => Promise<void>,
  options: { concurrency: number; startBefore: number; clock?: () => number },
): Promise<{ failures: unknown[]; deferred: number }> {
  const clock = options.clock ?? Date.now;
  let next = 0;
  const failures: unknown[] = [];
  await Promise.all(
    Array.from(
      { length: Math.min(items.length, options.concurrency) },
      async () => {
        while (next < items.length && clock() < options.startBefore) {
          const item = items[next++];
          try {
            await process(item);
          } catch (error) {
            failures.push(error);
          }
        }
      },
    ),
  );
  return { failures, deferred: items.length - next };
}
