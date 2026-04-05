import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./e2e",
  timeout: 30000,
  retries: 1,
  use: {
    baseURL: "http://localhost:3099",
    viewport: { width: 390, height: 844 },
    screenshot: "only-on-failure",
    trace: "on-first-retry",
  },
  projects: [
    {
      name: "chromium",
      use: { browserName: "chromium" },
    },
  ],
  webServer: [
    {
      command:
        'DATABASE_URL="postgresql+asyncpg://postgres:postgres@localhost:5433/fit_db" uv run uvicorn app.main:app --port 8099',
      cwd: "../backend",
      port: 8099,
      reuseExistingServer: true,
      timeout: 15000,
    },
    {
      command: "NEXT_PUBLIC_API_URL=http://localhost:8099 pnpm dev --port 3099",
      port: 3099,
      reuseExistingServer: true,
      timeout: 30000,
    },
  ],
});
