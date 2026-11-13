import { Hono } from "hono";
import type { AppEnv } from "../../context";
import { MAX_PAGE, MAX_PUSH, pull, push, SYNC_SCHEMA_VERSION } from "./sync.service";

/**
 * `POST /api/sync/push` takes `{ schemaVersion, changes: [{ table, row }] }` and answers
 * `{ accepted: [{ table, id, updated_at }], rejected: [{ table, id, reason }] }`.
 *
 * `GET /api/sync/pull?since=<seq>&limit=500&schemaVersion=1` answers `{ rows, next, hasMore }`.
 *
 * Both need a session, and both answer 426 when the app is built against an older schema than the server.
 */
export const syncRoutes = new Hono<AppEnv>()
  .post("/push", async (c) => {
    const body = await c.req.json().catch(() => null);
    if (!body || typeof body !== "object") return c.json({ error: "Send a JSON body." }, 400);
    const outdated = checkSchema(body.schemaVersion);
    if (outdated) return c.json({ error: outdated.message }, outdated.status);
    if (!Array.isArray(body.changes)) return c.json({ error: "changes must be a list." }, 400);
    if (body.changes.length > MAX_PUSH) return c.json({ error: `Send at most ${MAX_PUSH} changes at a time.` }, 400);
    for (const change of body.changes) {
      if (!change || typeof change !== "object" || typeof change.table !== "string" || !("row" in change)) {
        return c.json({ error: "Each change needs a table and a row." }, 400);
      }
    }
    return c.json(await push(c.var.db, c.var.session!.user.id, body.changes));
  })
  .get("/pull", async (c) => {
    const outdated = checkSchema(c.req.query("schemaVersion"));
    if (outdated) return c.json({ error: outdated.message }, outdated.status);
    const since = Number(c.req.query("since") ?? 0);
    if (!Number.isInteger(since) || since < 0) return c.json({ error: "since must be a whole number." }, 400);
    const limit = Number(c.req.query("limit") ?? MAX_PAGE);
    if (!Number.isInteger(limit) || limit < 1) return c.json({ error: "limit must be a whole number above 0." }, 400);
    return c.json(await pull(c.var.db, c.var.session!.user.id, since, limit));
  });

function checkSchema(raw: unknown): { status: 400 | 426; message: string } | null {
  const version = Number(raw);
  if (raw === undefined || raw === null || !Number.isInteger(version)) return { status: 400, message: "schemaVersion is missing." };
  if (version < SYNC_SCHEMA_VERSION) return { status: 426, message: "Update the app to sync." };
  if (version > SYNC_SCHEMA_VERSION) return { status: 400, message: "The API is older than the app. Deploy the API first." };
  return null;
}
