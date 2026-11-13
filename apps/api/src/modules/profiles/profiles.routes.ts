import { Hono, type Context } from "hono";
import type { AppEnv } from "../../context";
import { withPhotos } from "../../lib/photos";
import { requireSession } from "../../middleware/services";
import { byHandle, clearPhoto, getMine, preparePhoto, ProfileError, saveMine, search, setPhoto } from "./profiles.service";

/**
 * `GET /api/profiles/me` is your profile, or 404 before you've picked a handle.
 * `PUT /api/profiles/me` creates or changes it with `{ handle?, bio?, defaultVisibility? }`.
 * `GET /api/profiles/search?q=` finds people by the start of their handle.
 * `POST /api/profiles/me/photo/upload` with `{ id, byteSize }` returns where to send a new profile photo (a JPEG).
 * `PUT /api/profiles/me/photo` with the same body makes it your photo once it has arrived.
 * `DELETE /api/profiles/me/photo` removes it.
 * `GET /api/profiles/:handle` is someone's profile and how they relate to you.
 *
 * Every person comes with `photoUrl`, a download link that lasts an hour, or null.
 */
export const profileRoutes = new Hono<AppEnv>()
  .use(requireSession)
  .onError((error, c) => {
    if (!(error instanceof ProfileError)) throw error;
    const status = error.code === "handle_taken" ? 409 : error.code === "photo_not_uploaded" ? 409 : 400;
    return c.json({ error: error.code, message: error.message }, status);
  })
  .get("/me", async (c) => {
    const mine = await getMine(c.var.db, c.var.session!.user.id);
    return mine ? c.json(await one(c, mine)) : c.json({ error: "no_profile", message: "Pick a handle first." }, 404);
  })
  .put("/me", async (c) => {
    const body = await c.req.json().catch(() => null);
    if (!body || typeof body !== "object") return c.json({ error: "invalid_body", message: "Send the profile as JSON." }, 400);
    return c.json(await one(c, await saveMine(c.var.db, c.var.session!.user.id, body)));
  })
  .post("/me/photo/upload", async (c) => {
    if (!c.var.storage) return unavailable(c);
    const body = await c.req.json().catch(() => ({}));
    return c.json(await preparePhoto(c.var.db, c.var.storage, c.var.session!.user.id, body ?? {}));
  })
  .put("/me/photo", async (c) => {
    if (!c.var.storage) return unavailable(c);
    const body = await c.req.json().catch(() => ({}));
    return c.json(await one(c, await setPhoto(c.var.db, c.var.storage, c.var.session!.user.id, body ?? {})));
  })
  .delete("/me/photo", async (c) => {
    if (!c.var.storage) return unavailable(c);
    await clearPhoto(c.var.db, c.var.storage, c.var.session!.user.id);
    return c.body(null, 204);
  })
  .get("/search", async (c) => {
    const people = await search(c.var.db, c.var.session!.user.id, c.req.query("q") ?? "");
    return c.json(await withPhotos(c.var.db, c.var.storage, people));
  })
  .get("/:handle", async (c) => {
    const person = await byHandle(c.var.db, c.var.session!.user.id, c.req.param("handle"));
    return person ? c.json(await one(c, person)) : c.json({ error: "not_found", message: "There's nobody with that handle." }, 404);
  });

/** One person with their photo link. */
async function one<T extends { userId: string }>(c: Context<AppEnv>, person: T) {
  return (await withPhotos(c.var.db, c.var.storage, [person]))[0]!;
}

function unavailable(c: Context<AppEnv>) {
  return c.json({ error: "media_unavailable", message: "Photos aren't set up on this server." }, 503);
}
