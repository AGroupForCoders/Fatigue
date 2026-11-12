import { Hono } from "hono";
import type { AppEnv } from "./context";
import { services } from "./middleware/services";
import { authRoutes } from "./modules/auth/auth.routes";

/** Builds the API. Plain Hono, so it runs anywhere Hono does; only index.ts knows about Workers. */
export function createApp() {
  const app = new Hono<AppEnv>();

  app.get("/health", (c) => c.json({ ok: true }));

  app.use("/api/*", services);
  app.route("/api/auth", authRoutes);

  return app;
}
