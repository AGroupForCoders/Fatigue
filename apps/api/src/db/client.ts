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
  const client = postgres(url, { max: 1, prepare: false });
  return { db: drizzle(client, { schema }), close: () => client.end() };
}

export type Db = ReturnType<typeof createDb>["db"];
