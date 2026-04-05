import { test, expect } from "@playwright/test";

test.describe("Scan and Meal Logging", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/login");
    await page.getByLabel(/email/i).fill("test1@fittracker.dev");
    await page.getByLabel(/password/i).fill("test1234");
    await page.getByRole("button", { name: /log in|sign in/i }).click();
    await page.waitForURL("**/dashboard", { timeout: 15000 });
  });

  test("scan page renders with manual entry", async ({ page }) => {
    await page.goto("/scan");
    await expect(page.getByPlaceholder(/barcode/i)).toBeVisible({ timeout: 5000 });
  });

  test("manual barcode entry accepts numeric input", async ({ page }) => {
    await page.goto("/scan");
    // Input has pattern="[0-9]*" so only numeric barcodes are valid
    await page.getByPlaceholder(/barcode/i).fill("7501000000001");
    const searchBtn = page.getByRole("button", { name: /search|submit|look/i });
    await expect(searchBtn).toBeEnabled();
  });

  test("meals page shows logged meals", async ({ page }) => {
    await page.goto("/meals");
    // Seeded data uses Spanish meal types: Desayuno, Almuerzo, Cena
    await expect(page.getByText(/desayuno|almuerzo|cena|breakfast|lunch|dinner/i).first()).toBeVisible({ timeout: 10000 });
  });

  test("meals page shows date navigation", async ({ page }) => {
    await page.goto("/meals");
    // Should have date selector or date display
    const dateContent = page.locator("input[type='date'], [class*='date']");
    await expect(dateContent.first()).toBeVisible({ timeout: 5000 });
  });
});
