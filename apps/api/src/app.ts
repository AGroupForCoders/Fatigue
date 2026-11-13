import { Hono } from "hono";
import type { AppEnv } from "./context";
import { requireSession, services } from "./middleware/services";
import { authRoutes } from "./modules/auth/auth.routes";
import { syncRoutes } from "./modules/sync/sync.routes";

/** Builds the API. Plain Hono, so it runs anywhere Hono does; only index.ts knows about Workers. */
export function createApp() {
  const app = new Hono<AppEnv>();

  app.get("/health", (c) => c.json({ ok: true }));

  app.use("/api/*", services);
  app.route("/api/auth", authRoutes);
  app.use("/api/sync/*", requireSession);
  app.route("/api/sync", syncRoutes);

  return app;
}
