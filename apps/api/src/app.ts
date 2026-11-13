import { Hono } from "hono";
import type { AppEnv } from "./context";
import { services } from "./middleware/services";
import { authPages } from "./modules/auth/auth.pages";
import { authRoutes } from "./modules/auth/auth.routes";
import { friendRoutes } from "./modules/friends/friends.routes";
import { postRoutes } from "./modules/posts/posts.routes";
import { profileRoutes } from "./modules/profiles/profiles.routes";

/** Builds the API. Plain Hono, so it runs anywhere Hono does; only index.ts knows about Workers. */
export function createApp() {
  const app = new Hono<AppEnv>();

  app.get("/health", (c) => c.json({ ok: true }));

  // Landing pages for the links in emails. No database needed, so they sit outside /api.
  app.route("/auth", authPages);

  app.use("/api/*", services);
  app.route("/api/auth", authRoutes);
  app.route("/api/profiles", profileRoutes);
  app.route("/api/friends", friendRoutes);
  app.route("/api/posts", postRoutes);

  return app;
}
