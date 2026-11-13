import { defineConfig } from "drizzle-kit";

// Only migrate needs a database; generate works without a .env.
try {
  process.loadEnvFile?.(".env");
} catch {}

export default defineConfig({
  dialect: "postgresql",
  schema: "./src/db/schema/index.ts",
  out: "./src/db/migrations",
  dbCredentials: { url: process.env.DATABASE_URL ?? "" },
});
