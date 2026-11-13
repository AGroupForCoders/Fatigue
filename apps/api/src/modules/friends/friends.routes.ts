import { Hono } from "hono";
import type { AppEnv } from "../../context";
import { withPhotos } from "../../lib/photos";
import { requireSession } from "../../middleware/services";
import { accept, FriendError, list, remove, request } from "./friends.service";

/**
 * `GET /api/friends` lists your friends and requests both ways.
 * `POST /api/friends/:userId` sends a request, or accepts theirs if they already sent one.
 * `POST /api/friends/:userId/accept` accepts their request.
 * `DELETE /api/friends/:userId` declines, takes back a request, or unfriends.
 */
export const friendRoutes = new Hono<AppEnv>()
  .use(requireSession)
  .get("/", async (c) => c.json(await withPhotos(c.var.db, c.var.storage, await list(c.var.db, c.var.session!.user.id))))
  .post("/:userId", async (c) => {
    try {
      return c.json({ relation: await request(c.var.db, c.var.session!.user.id, c.req.param("userId")) });
    } catch (error) {
      return failed(error);
    }
  })
  .post("/:userId/accept", async (c) => {
    try {
      return c.json({ relation: await accept(c.var.db, c.var.session!.user.id, c.req.param("userId")) });
    } catch (error) {
      return failed(error);
    }
  })
  .delete("/:userId", async (c) => {
    await remove(c.var.db, c.var.session!.user.id, c.req.param("userId"));
    return c.body(null, 204);
  });

function failed(error: unknown) {
  if (!(error instanceof FriendError)) throw error;
  const status = error.code === "not_found" ? 404 : error.code === "no_request" ? 409 : 400;
  return Response.json({ error: error.code, message: error.message }, { status });
}
