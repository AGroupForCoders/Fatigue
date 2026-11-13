import { PGlite } from "@electric-sql/pglite";
import { drizzle } from "drizzle-orm/pglite";
import { migrate } from "drizzle-orm/pglite/migrator";
import { fileURLToPath } from "node:url";
import type { Database } from "./client";
import * as schema from "./schema";
import { user } from "./schema";

/**
 * A fresh Postgres in memory with every migration applied, for service tests. Each call is its own
 * database, so tests never see each other's rows.
 */
export async function testDb(): Promise<Database> {
  const db = drizzle(new PGlite(), { schema });
  await migrate(db, { migrationsFolder: fileURLToPath(new URL("./migrations", import.meta.url)) });
  return db as unknown as Database;
}

/** Adds an account the way Better Auth would, and returns its ID. */
export async function addUser(db: Database, id: string, name = id) {
  await db.insert(user).values({ id, name, email: `${id}@example.com` });
  return id;
}
