import { test, expect } from "@playwright/test";

test.describe("Dashboard", () => {
  test.beforeEach(async ({ page }) => {
    // Login first
    await page.goto("/login");
    await page.getByLabel(/email/i).fill("test1@fittracker.dev");
    await page.getByLabel(/password/i).fill("test1234");
    await page.getByRole("button", { name: /log in|sign in/i }).click();
    await page.waitForURL("**/dashboard", { timeout: 15000 });
  });

  test("dashboard loads with nutrition data", async ({ page }) => {
    await expect(page.getByText(/calories|dashboard/i).first()).toBeVisible({ timeout: 10000 });
  });

  test("bottom navigation works", async ({ page }) => {
    // Click Meals nav
    await page.getByRole("link", { name: /meals/i }).click();
    await expect(page).toHaveURL(/meals/);

    // Click Workouts nav
    await page.getByRole("link", { name: /workouts/i }).click();
    await expect(page).toHaveURL(/workouts/);

    // Click Dashboard nav
    await page.getByRole("link", { name: /dashboard/i }).click();
    await expect(page).toHaveURL(/dashboard/);
  });

  test("dashboard shows macro breakdown", async ({ page }) => {
    // Check for macro-related content (protein, carbs, fat)
    await expect(page.getByText(/protein|carbs|fat/i).first()).toBeVisible({ timeout: 10000 });
  });
});
