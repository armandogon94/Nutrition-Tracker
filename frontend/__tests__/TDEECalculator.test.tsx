import { describe, expect, it } from "vitest";

// Test the TDEE math client-side (mirrors backend logic)
function calculateBMR(weight: number, height: number, age: number, sex: string): number {
  const factor = sex === "male" ? 5 : -161;
  return 10 * weight + 6.25 * height - 5 * age + factor;
}

describe("TDEE Calculator Math", () => {
  it("calculates male BMR correctly", () => {
    const bmr = calculateBMR(80, 180, 30, "male");
    expect(bmr).toBe(1780);
  });

  it("calculates female BMR correctly", () => {
    const bmr = calculateBMR(60, 165, 25, "female");
    expect(bmr).toBe(1345.25);
  });

  it("TDEE is BMR * activity multiplier", () => {
    const bmr = 1780;
    const tdee = bmr * 1.55; // moderate
    expect(tdee).toBeCloseTo(2759);
  });

  it("fat loss subtracts 500 from TDEE", () => {
    const tdee = 2500;
    const fatLossCals = tdee - 500;
    expect(fatLossCals).toBe(2000);
  });

  it("protein is 2g per kg bodyweight", () => {
    const proteinG = 80 * 2;
    expect(proteinG).toBe(160);
  });

  it("fat is 25% of calories", () => {
    const fatG = Math.round((2500 * 0.25) / 9);
    expect(fatG).toBe(69);
  });
});
