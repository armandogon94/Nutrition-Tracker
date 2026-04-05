import { test, expect } from "@playwright/test";

test.describe("Profile and Goals", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/login");
    await page.getByLabel(/email/i).fill("test1@fittracker.dev");
    await page.getByLabel(/password/i).fill("test1234");
    await page.getByRole("button", { name: /log in|sign in/i }).click();
    await page.waitForURL("**/dashboard", { timeout: 15000 });
  });

  test("profile page has form fields", async ({ page }) => {
    await page.goto("/profile");
    await expect(page.getByText(/weight|height|age/i).first()).toBeVisible({ timeout: 5000 });
  });

  test("TDEE calculator produces results", async ({ page }) => {
    await page.goto("/profile");
    // The seeded profile should already have TDEE data
    await expect(page.getByText(/tdee|bmr|calories/i).first()).toBeVisible({ timeout: 10000 });
  });

  test("goals page loads with saved goals", async ({ page }) => {
    await page.goto("/goals");
    // Seeded goals should be visible
    await expect(page.getByText(/calories|protein|carbs|fat/i).first()).toBeVisible({ timeout: 10000 });
  });
});
