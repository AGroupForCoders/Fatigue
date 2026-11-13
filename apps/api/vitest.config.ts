import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // Service tests start an in-memory Postgres and run every migration first, which can pass 5 seconds on a busy CI runner.
    testTimeout: 30_000,
  },
});
