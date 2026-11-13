import type { PgDatabase, PgQueryResultHKT } from "drizzle-orm/pg-core";
import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import * as schema from "./schema";

/**
 * Opens a database client for one request.
 *
 * Workers can't share a connection between requests, so each request gets its own and closes it
 * when the response is done. On a long-running host this would become one shared pool instead,
 * and this file is the only place that would change.
 */
export function createDb(url: string) {
  const client = postgres(withoutChannelBinding(url), { max: 1, prepare: false });
  return { db: drizzle(client, { schema }), close: () => client.end() };
}

export type Db = ReturnType<typeof createDb>["db"];

/**
 * Any Drizzle Postgres database with our schema. Services take this instead of `Db`, so tests can hand
 * them PGlite (Postgres in memory) and the app hands them postgres.js.
 */
export type Database = PgDatabase<PgQueryResultHKT, typeof schema>;

/**
 * Neon's copied connection strings end with `channel_binding=require`. postgres.js can't do channel
 * binding inside Workers, so Neon closes the connection and every query fails with CONNECTION_CLOSED.
 * The connection is still encrypted by `sslmode=require`.
 */
export function withoutChannelBinding(url: string) {
  const parsed = new URL(url);
  parsed.searchParams.delete("channel_binding");
  return parsed.toString();
}
