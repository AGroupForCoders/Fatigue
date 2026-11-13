import { Hono } from "hono";
import type { AppEnv } from "../../context";
import { requireSession } from "../../middleware/services";
import { byAuthor, feed, get, PostError, remove, share } from "./posts.service";

/**
 * `GET /api/posts/feed?cursor=` is your posts and your friends' posts, newest workout first, 20 a page.
 * `GET /api/posts/by/:userId?cursor=` is someone's posts that you can see.
 * `GET /api/posts/:id` is one post, if you can see it.
 * `PUT /api/posts/:id` shares a workout, or shares it again. The phone makes the ID.
 * `DELETE /api/posts/:id` deletes your post.
 */
export const postRoutes = new Hono<AppEnv>()
  .use(requireSession)
  .onError((error, c) => {
    if (!(error instanceof PostError)) throw error;
    const status = error.code === "not_found" ? 404 : error.code === "deleted" ? 410 : 400;
    return c.json({ error: error.code, message: error.message }, status);
  })
  .get("/feed", async (c) => c.json(await feed(c.var.db, c.var.session!.user.id, c.req.query("cursor"))))
  .get("/by/:userId", async (c) => c.json(await byAuthor(c.var.db, c.var.session!.user.id, c.req.param("userId"), c.req.query("cursor"))))
  .get("/:id", async (c) => {
    const found = await get(c.var.db, c.var.session!.user.id, c.req.param("id"));
    return found ? c.json(found) : c.json({ error: "not_found", message: "There's no post with that ID." }, 404);
  })
  .put("/:id", async (c) => {
    const body = await c.req.json().catch(() => null);
    if (!body || typeof body !== "object") return c.json({ error: "invalid", message: "Send the post as JSON." }, 400);
    return c.json(await share(c.var.db, c.var.session!.user.id, c.req.param("id"), body));
  })
  .delete("/:id", async (c) => {
    await remove(c.var.db, c.var.session!.user.id, c.req.param("id"));
    return c.body(null, 204);
  });
