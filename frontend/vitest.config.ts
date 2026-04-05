import react from "@vitejs/plugin-react";
import { resolve } from "path";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: { "@": resolve(__dirname, ".") },
  },
  css: {
    postcss: {
      plugins: [],
    },
  },
  test: {
    globals: true,
    environment: "jsdom",
    setupFiles: ["./__tests__/setup.ts"],
    css: false,
    exclude: ["**/node_modules/**", "**/e2e/**", "**/*.spec.ts"],
  },
});
