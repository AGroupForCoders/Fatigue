import { Hono } from "hono";
import type { AppEnv } from "../../context";
import { requireSession } from "../../middleware/services";
import { pageSize, pull, push } from "./sync.service";

/**
 * `POST /api/sync/push` takes `{ schema, items }`, up to 100 items, and answers `{ results }` with one
 * entry per item in the same order. `schema` is the schema of the build that is pushing.
 * `GET /api/sync/pull?cursor=` answers `{ items, cursor, more }`: the items changed since `cursor`,
 * the cursor to send next time, and whether to ask again straight away. A first pull sends no cursor.
 *
 * The Sync docs page has the rules.
 */
export const syncRoutes = new Hono<AppEnv>()
  .use(requireSession)
  .post("/push", async (c) => {
    const body = await c.req.json().catch(() => null);
    if (!body || typeof body !== "object" || !Number.isSafeInteger(body.schema) || !Array.isArray(body.items)) {
      return c.json({ error: "invalid_body", message: "Send { schema, items } as JSON." }, 400);
    }
    if (body.items.length > pageSize) return c.json({ error: "too_many", message: `Send at most ${pageSize} items at a time.` }, 400);
    return c.json({ results: await push(c.var.db, c.var.session!.user.id, body.schema, body.items) });
  })
  .get("/pull", async (c) => {
    const cursor = Number(c.req.query("cursor") ?? 0);
    if (!Number.isSafeInteger(cursor) || cursor < 0) return c.json({ error: "invalid_cursor", message: "The cursor is the number the last pull gave back." }, 400);
    return c.json(await pull(c.var.db, c.var.session!.user.id, cursor));
  });
