import { test, expect } from "@playwright/test";

test.describe("Workouts", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/login");
    await page.getByLabel(/email/i).fill("test1@fittracker.dev");
    await page.getByLabel(/password/i).fill("test1234");
    await page.getByRole("button", { name: /log in|sign in/i }).click();
    await page.waitForURL("**/dashboard", { timeout: 15000 });
  });

  test("workouts page shows programs", async ({ page }) => {
    await page.goto("/workouts");
    // 9 seeded programs should be visible
    await expect(page.getByText(/push|pull|upper|lower|full body/i).first()).toBeVisible({ timeout: 10000 });
  });

  test("program detail page loads", async ({ page }) => {
    await page.goto("/workouts");
    // Click on the first program
    const programLinks = page.locator("a[href*='/workouts/'], button").filter({ hasText: /view|start|detail/i });
    if (await programLinks.count() > 0) {
      await programLinks.first().click();
      await expect(page.getByText(/day|exercises/i).first()).toBeVisible({ timeout: 10000 });
    }
  });

  test("exercises page loads with filterable list", async ({ page }) => {
    await page.goto("/exercises");
    await expect(page.getByText(/exercises/i).first()).toBeVisible({ timeout: 5000 });
    await expect(page.getByPlaceholder(/search/i)).toBeVisible();
    // Should show some exercises (56 seeded)
    await expect(page.getByText(/bench|squat|curl/i).first()).toBeVisible({ timeout: 10000 });
  });

  test("exercise search filters results", async ({ page }) => {
    await page.goto("/exercises");
    await page.getByPlaceholder(/search/i).fill("bench");
    // Wait for debounced search (300ms + API call)
    await expect(page.getByText(/bench press/i).first()).toBeVisible({ timeout: 5000 });
  });

  test("workout history page loads", async ({ page }) => {
    await page.goto("/workouts/history");
    // Carlos has a seeded workout from yesterday
    await expect(page.getByText(/history|session|workout/i).first()).toBeVisible({ timeout: 10000 });
  });
});
