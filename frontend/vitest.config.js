import { defineConfig } from "vitest/config";

export default defineConfig({
  esbuild: { jsx: "automatic" },
  test: {
    environment: "jsdom",
    include: ["src/**/*.test.{js,jsx}"],
    setupFiles: ["src/test/setup.js"],
    // Above Testing Library's 10s async wait (src/test/setup.js), so a slow
    // findBy fails with its own message instead of a bare test timeout.
    testTimeout: 15000,
  },
});
