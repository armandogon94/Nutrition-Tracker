import { describe, expect, it, vi, beforeEach, afterEach } from "vitest";

describe("Rest Timer Logic", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("calculates remaining time from start timestamp", () => {
    const startTime = Date.now();
    const duration = 90000; // 90 seconds in ms

    vi.advanceTimersByTime(30000); // advance 30 seconds

    const elapsed = Date.now() - startTime;
    const remaining = Math.max(0, duration - elapsed);

    expect(remaining).toBe(60000); // 60 seconds left
  });

  it("returns 0 when timer has expired", () => {
    const startTime = Date.now();
    const duration = 90000;

    vi.advanceTimersByTime(100000); // advance 100 seconds

    const elapsed = Date.now() - startTime;
    const remaining = Math.max(0, duration - elapsed);

    expect(remaining).toBe(0);
  });

  it("handles exact duration completion", () => {
    const startTime = Date.now();
    const duration = 60000;

    vi.advanceTimersByTime(60000);

    const elapsed = Date.now() - startTime;
    const remaining = Math.max(0, duration - elapsed);

    expect(remaining).toBe(0);
  });
});
