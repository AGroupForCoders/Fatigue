import { Hono } from "hono";
import type { AppEnv } from "../../context";

/**
 * Better Auth's own endpoints, such as `POST /api/auth/sign-up/email`, `POST /api/auth/sign-in/email`,
 * `GET /api/auth/get-session`, `POST /api/auth/sign-out`, `POST /api/auth/update-user`,
 * `POST /api/auth/delete-user`, `POST /api/auth/request-password-reset`, `POST /api/auth/reset-password`
 * and `POST /api/auth/send-verification-email`. The links in the emails come back to
 * `GET /api/auth/reset-password/:token` and `GET /api/auth/verify-email`, which redirect to auth.pages.ts.
 */
export const authRoutes = new Hono<AppEnv>().on(["GET", "POST"], "/*", (c) => c.var.auth.handler(c.req.raw));
