import { Hono } from "hono";
import type { AppEnv } from "../../context";
import { requireSession } from "../../middleware/services";
import { byHandle, getMine, ProfileError, saveMine, search } from "./profiles.service";

/**
 * `GET /api/profiles/me` is your profile, or 404 before you've picked a handle.
 * `PUT /api/profiles/me` creates or changes it with `{ handle?, bio?, defaultVisibility? }`.
 * `GET /api/profiles/search?q=` finds people by the start of their handle.
 * `GET /api/profiles/:handle` is someone's profile and how they relate to you.
 */
export const profileRoutes = new Hono<AppEnv>()
  .use(requireSession)
  .get("/me", async (c) => {
    const mine = await getMine(c.var.db, c.var.session!.user.id);
    return mine ? c.json(mine) : c.json({ error: "no_profile", message: "Pick a handle first." }, 404);
  })
  .put("/me", async (c) => {
    const body = await c.req.json().catch(() => null);
    if (!body || typeof body !== "object") return c.json({ error: "invalid_body", message: "Send the profile as JSON." }, 400);
    try {
      return c.json(await saveMine(c.var.db, c.var.session!.user.id, body));
    } catch (error) {
      if (error instanceof ProfileError) return c.json({ error: error.code, message: error.message }, error.code === "handle_taken" ? 409 : 400);
      throw error;
    }
  })
  .get("/search", async (c) => c.json(await search(c.var.db, c.var.session!.user.id, c.req.query("q") ?? "")))
  .get("/:handle", async (c) => {
    const person = await byHandle(c.var.db, c.var.session!.user.id, c.req.param("handle"));
    return person ? c.json(person) : c.json({ error: "not_found", message: "There's nobody with that handle." }, 404);
  });
