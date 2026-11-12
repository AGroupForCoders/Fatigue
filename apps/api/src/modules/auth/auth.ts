import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { bearer } from "better-auth/plugins";
import type { Db } from "../../db/client";
import * as schema from "../../db/schema";

type AuthOptions = { secret: string; baseURL: string };

/**
 * Better Auth for email and password sign-in.
 *
 * The iOS app keeps no cookies, so the bearer plugin hands back a session token on sign-in
 * (in the `set-auth-token` header) and accepts it as `Authorization: Bearer <token>` afterwards.
 */
export function createAuth(db: Db, options: AuthOptions) {
  return betterAuth({
    secret: options.secret,
    baseURL: options.baseURL,
    database: drizzleAdapter(db, { provider: "pg", schema }),
    emailAndPassword: {
      enabled: true,
      minPasswordLength: 8,
      // Sign-up signs you straight in. Email verification can come once we send email.
      autoSignIn: true,
    },
    user: {
      // Lets someone delete their own account from the profile screen, confirmed with their password.
      deleteUser: { enabled: true },
    },
    session: {
      // A phone stays signed in for 90 days, and each use within that time pushes it back.
      expiresIn: 60 * 60 * 24 * 90,
      updateAge: 60 * 60 * 24,
    },
    plugins: [bearer()],
  });
}

export type Auth = ReturnType<typeof createAuth>;
export type Session = Auth["$Infer"]["Session"];
