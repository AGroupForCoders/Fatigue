import { PGlite } from "@electric-sql/pglite";
import { drizzle } from "drizzle-orm/pglite";
import { migrate } from "drizzle-orm/pglite/migrator";
import { Hono } from "hono";
import { fileURLToPath } from "node:url";
import type { AppEnv } from "../context";
import * as schema from "../db/schema";
import type { Session } from "../modules/auth/auth";

/**
 * A real Postgres in memory for tests, with the migrations applied. PGlite runs Postgres compiled to
 * WebAssembly, so the SQL the tests exercise is the SQL production runs, with no server to start.
 */
export async function testDb() {
  const client = new PGlite();
  const db = drizzle(client, { schema });
  await migrate(db, { migrationsFolder: fileURLToPath(new URL("../db/migrations", import.meta.url)) });
  return { db, close: () => client.close() };
}

export type TestDb = Awaited<ReturnType<typeof testDb>>["db"];

export async function createUser(db: TestDb, id: string) {
  await db.insert(schema.user).values({ id, name: id, email: `${id}@example.com` });
}

/**
 * Mounts routes the way app.ts does, but with the test database and a signed-in user instead of
 * Better Auth. The user is taken from the `X-Test-User` header, so one app can serve two accounts.
 */
export function testApp(db: TestDb, path: string, routes: Hono<AppEnv>) {
  const app = new Hono<AppEnv>();
  app.use(`${path}/*`, async (c, next) => {
    c.set("db", db as never);
    const userId = c.req.header("X-Test-User");
    if (!userId) return c.json({ error: "Sign in first." }, 401);
    c.set("session", { user: { id: userId } } as Session);
    await next();
  });
  app.route(path, routes);
  return app;
}
