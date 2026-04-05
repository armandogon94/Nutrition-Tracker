import { test, expect } from "@playwright/test";

const TEST_USER = { email: "test1@fittracker.dev", password: "test1234" };

test.describe("Authentication", () => {
  test("login page renders", async ({ page }) => {
    await page.goto("/login");
    await expect(page.getByLabel(/email/i)).toBeVisible();
    await expect(page.getByLabel(/password/i)).toBeVisible();
  });

  test("login with valid credentials redirects to dashboard", async ({ page }) => {
    await page.goto("/login");
    await page.getByLabel(/email/i).fill(TEST_USER.email);
    await page.getByLabel(/password/i).fill(TEST_USER.password);
    await page.getByRole("button", { name: /log in|sign in/i }).click();
    await page.waitForURL("**/dashboard", { timeout: 15000 });
    await expect(page).toHaveURL(/dashboard/);
  });

  test("login with wrong password shows error", async ({ page }) => {
    await page.goto("/login");
    await page.getByLabel(/email/i).fill(TEST_USER.email);
    await page.getByLabel(/password/i).fill("wrongpassword");
    await page.getByRole("button", { name: /log in|sign in/i }).click();
    await expect(page.getByText(/invalid|error|wrong/i)).toBeVisible({ timeout: 5000 });
  });

  test("quick login buttons work", async ({ page }) => {
    await page.goto("/login");
    const quickButtons = page.getByRole("button").filter({ hasText: /test 1|test1|carlos/i });
    if (await quickButtons.count() > 0) {
      await quickButtons.first().click();
      await page.waitForURL("**/dashboard", { timeout: 15000 });
      await expect(page).toHaveURL(/dashboard/);
    }
  });
});
