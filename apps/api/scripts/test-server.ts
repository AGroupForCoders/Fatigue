// The real API on an in-memory Postgres, for tests that need a server end to end, such as the iOS
// two-phone sync tests. Nothing is kept: every start is an empty database with every migration applied.
//
//   pnpm --filter @fatigue/api test:server            # listens on http://localhost:8788
//
// PGlite runs the database inside this process, and pglite-socket puts it behind a Postgres port, so the
// API connects with postgres.js exactly as it does in production. Only the host is different: Node here
// instead of Workers.

import { PGlite } from "@electric-sql/pglite";
import { PGLiteSocketServer } from "@electric-sql/pglite-socket";
import { serve } from "@hono/node-server";
import { drizzle } from "drizzle-orm/pglite";
import { migrate } from "drizzle-orm/pglite/migrator";
import { fileURLToPath } from "node:url";
import { createApp } from "../src/app";
import type { Bindings } from "../src/env";

const port = Number(process.env.PORT ?? 8788);
const dbPort = Number(process.env.DB_PORT ?? 54329);

const pglite = new PGlite();
await migrate(drizzle(pglite), { migrationsFolder: fileURLToPath(new URL("../src/db/migrations", import.meta.url)) });
const socket = new PGLiteSocketServer({ db: pglite, port: dbPort, maxConnections: 20 });
await socket.start();

const env: Bindings = {
  DATABASE_URL: `postgres://postgres:postgres@127.0.0.1:${dbPort}/postgres`,
  BETTER_AUTH_SECRET: "test-server-secret-not-for-production-0000",
  BETTER_AUTH_URL: `http://localhost:${port}`,
};

const app = createApp();
serve({ fetch: (request) => app.fetch(request, env), port }, () => {
  console.log(`Test API on http://localhost:${port}`);
});
