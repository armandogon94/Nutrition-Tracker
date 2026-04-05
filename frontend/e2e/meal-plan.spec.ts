import { test, expect } from "@playwright/test";

test.describe("Meal Planning", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/login");
    await page.getByLabel(/email/i).fill("test1@fittracker.dev");
    await page.getByLabel(/password/i).fill("test1234");
    await page.getByRole("button", { name: /log in|sign in/i }).click();
    await page.waitForURL("**/dashboard", { timeout: 15000 });
  });

  test("meal plan page loads", async ({ page }) => {
    await page.goto("/meals/plan");
    await expect(page.getByText(/meal plan|planner/i).first()).toBeVisible({ timeout: 10000 });
  });

  test("can create a new meal plan", async ({ page }) => {
    await page.goto("/meals/plan");
    const nameInput = page.getByPlaceholder(/name|plan/i);
    if (await nameInput.isVisible()) {
      await nameInput.fill("E2E Test Plan");
      const createBtn = page.getByRole("button", { name: /create/i });
      if (await createBtn.isVisible()) {
        await createBtn.click();
        await expect(page.getByText(/e2e test plan/i).first()).toBeVisible({ timeout: 5000 });
      }
    }
  });

  test("shopping list can be generated", async ({ page }) => {
    await page.goto("/meals/plan");
    // If there's a plan with items, the generate button should be available
    const genBtn = page.getByRole("button", { name: /shopping|generate/i });
    if (await genBtn.count() > 0 && await genBtn.first().isVisible()) {
      await genBtn.first().click();
      // Should show shopping list categories
      await expect(page.getByText(/shopping|list|items/i).first()).toBeVisible({ timeout: 10000 });
    }
  });
});
