import { createMiddleware } from "hono/factory";
import type { AppEnv } from "../context";
import { createDb } from "../db/client";
import { createAuth } from "../modules/auth/auth";

/**
 * Opens the database and Better Auth for this request, and looks up the session from the
 * `Authorization: Bearer` header if there is one. Routes then read `c.var.session`.
 */
export const services = createMiddleware<AppEnv>(async (c, next) => {
  const { db, close } = createDb(c.env.DATABASE_URL);
  const auth = createAuth(db, { secret: c.env.BETTER_AUTH_SECRET, baseURL: c.env.BETTER_AUTH_URL });
  c.set("db", db);
  c.set("auth", auth);
  c.set("session", null);
  try {
    await next();
  } finally {
    // Close after the response is sent, so closing never delays it.
    const closing = close();
    try {
      c.executionCtx.waitUntil(closing);
    } catch {
      await closing;
    }
  }
});

/** Rejects the request with 401 unless it carries a valid session. */
export const requireSession = createMiddleware<AppEnv>(async (c, next) => {
  const session = await c.var.auth.api.getSession({ headers: c.req.raw.headers });
  if (!session) return c.json({ error: "Sign in first." }, 401);
  c.set("session", session);
  await next();
});
