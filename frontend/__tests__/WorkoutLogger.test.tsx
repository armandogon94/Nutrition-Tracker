import { describe, expect, it } from "vitest";

// Test the 1RM estimation formulas
function estimateBrzycki(weight: number, reps: number): number {
  if (reps <= 0 || weight <= 0) return 0;
  if (reps === 1) return weight;
  return weight * (36 / (37 - reps));
}

function estimateEpley(weight: number, reps: number): number {
  if (reps <= 0 || weight <= 0) return 0;
  if (reps === 1) return weight;
  return weight * (1 + reps / 30);
}

function estimate1RM(weight: number, reps: number): number {
  return (estimateBrzycki(weight, reps) + estimateEpley(weight, reps)) / 2;
}

describe("1RM Estimation", () => {
  it("returns exact weight for 1 rep", () => {
    expect(estimate1RM(100, 1)).toBe(100);
  });

  it("returns 0 for 0 weight", () => {
    expect(estimate1RM(0, 5)).toBe(0);
  });

  it("returns 0 for 0 reps", () => {
    expect(estimate1RM(100, 0)).toBe(0);
  });

  it("estimates higher 1RM for more reps at same weight", () => {
    const e1rm5 = estimate1RM(100, 5);
    const e1rm10 = estimate1RM(100, 10);
    expect(e1rm10).toBeGreaterThan(e1rm5);
  });

  it("100kg x 5 estimates around 115-120kg", () => {
    const e1rm = estimate1RM(100, 5);
    expect(e1rm).toBeGreaterThan(110);
    expect(e1rm).toBeLessThan(125);
  });

  it("Brzycki and Epley give same result at 10 reps", () => {
    const brzycki = estimateBrzycki(100, 10);
    const epley = estimateEpley(100, 10);
    expect(brzycki).toBeCloseTo(epley, 0);
  });
});
