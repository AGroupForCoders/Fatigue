import { Hono } from "hono";
import type { AppEnv } from "../../context";

/**
 * Better Auth's own endpoints, such as `POST /api/auth/sign-up/email`, `POST /api/auth/sign-in/email`,
 * `GET /api/auth/get-session`, `POST /api/auth/sign-out`, `POST /api/auth/update-user`
 * and `POST /api/auth/delete-user`.
 */
export const authRoutes = new Hono<AppEnv>().on(["GET", "POST"], "/*", (c) => c.var.auth.handler(c.req.raw));
