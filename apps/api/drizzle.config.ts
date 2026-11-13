import { defineConfig } from "drizzle-kit";

// Local dev keeps DATABASE_URL in .env. On deploy there is no .env and the URL comes from the
// environment, so a missing file is fine.
try {
  process.loadEnvFile?.(".env");
} catch {}

export default defineConfig({
  dialect: "postgresql",
  schema: "./src/db/schema/index.ts",
  out: "./src/db/migrations",
  dbCredentials: { url: process.env.DATABASE_URL ?? "" },
});
