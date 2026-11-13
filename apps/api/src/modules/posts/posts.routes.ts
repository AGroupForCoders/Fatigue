import { Hono, type Context } from "hono";
import type { AppEnv } from "../../context";
import { requireSession } from "../../middleware/services";
import { completeUpload, MediaError, prepareUpload, removeMedia } from "./media.service";
import { byAuthor, feed, get, PostError, remove, share } from "./posts.service";

/**
 * `GET /api/posts/feed?cursor=` is your posts and your friends' posts, newest workout first, 20 a page.
 * `GET /api/posts/by/:userId?cursor=` is someone's posts that you can see.
 * `GET /api/posts/:id` is one post, if you can see it.
 * `PUT /api/posts/:id` shares a workout, or shares it again. The phone makes the ID.
 * `DELETE /api/posts/:id` deletes your post.
 *
 * Photos and videos on your post, up to three. The phone makes each ID:
 * `PUT /api/posts/:id/media/:mediaId` with `{ kind, contentType, byteSize, width?, height?, durationSeconds?, position }`
 * returns `{ id, status, upload? }`, where `upload` is `{ url, method, headers, expiresAt }` to send the file to.
 * `POST /api/posts/:id/media/:mediaId/complete` checks the file arrived and shows it on the post.
 * `DELETE /api/posts/:id/media/:mediaId` takes it off the post.
 *
 * Every post comes with `media`, its finished photos and videos with download links that last an hour.
 */
export const postRoutes = new Hono<AppEnv>()
  .use(requireSession)
  .onError((error, c) => {
    if (error instanceof MediaError) {
      const status = { not_found: 404, deleted: 410, removed: 410, not_uploaded: 409, too_many: 409, invalid: 400 } as const;
      return c.json({ error: error.code, message: error.message }, status[error.code]);
    }
    if (!(error instanceof PostError)) throw error;
    const status = error.code === "not_found" ? 404 : error.code === "deleted" ? 410 : 400;
    return c.json({ error: error.code, message: error.message }, status);
  })
  .get("/feed", async (c) => c.json(await feed(c.var.db, c.var.session!.user.id, c.req.query("cursor"), c.var.storage)))
  .get("/by/:userId", async (c) =>
    c.json(await byAuthor(c.var.db, c.var.session!.user.id, c.req.param("userId"), c.req.query("cursor"), c.var.storage)),
  )
  .put("/:id/media/:mediaId", async (c) => {
    if (!c.var.storage) return unavailable(c);
    const body = await c.req.json().catch(() => null);
    if (!body || typeof body !== "object") return c.json({ error: "invalid", message: "Send the file's details as JSON." }, 400);
    return c.json(await prepareUpload(c.var.db, c.var.storage, c.var.session!.user.id, c.req.param("id"), c.req.param("mediaId"), body));
  })
  .post("/:id/media/:mediaId/complete", async (c) => {
    if (!c.var.storage) return unavailable(c);
    return c.json(await completeUpload(c.var.db, c.var.storage, c.var.session!.user.id, c.req.param("id"), c.req.param("mediaId")));
  })
  .delete("/:id/media/:mediaId", async (c) => {
    if (!c.var.storage) return unavailable(c);
    await removeMedia(c.var.db, c.var.storage, c.var.session!.user.id, c.req.param("id"), c.req.param("mediaId"));
    return c.body(null, 204);
  })
  .get("/:id", async (c) => {
    const found = await get(c.var.db, c.var.session!.user.id, c.req.param("id"), c.var.storage);
    return found ? c.json(found) : c.json({ error: "not_found", message: "There's no post with that ID." }, 404);
  })
  .put("/:id", async (c) => {
    const body = await c.req.json().catch(() => null);
    if (!body || typeof body !== "object") return c.json({ error: "invalid", message: "Send the post as JSON." }, 400);
    return c.json(await share(c.var.db, c.var.session!.user.id, c.req.param("id"), body, c.var.storage));
  })
  .delete("/:id", async (c) => {
    await remove(c.var.db, c.var.session!.user.id, c.req.param("id"));
    return c.body(null, 204);
  });

function unavailable(c: Context<AppEnv>) {
  return c.json({ error: "media_unavailable", message: "Photos and videos aren't set up on this server." }, 503);
}
