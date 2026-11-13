import { betterAuth, type BetterAuthOptions } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { bearer } from "better-auth/plugins";
import type { Db } from "../../db/client";
import * as schema from "../../db/schema";
import type { Mailer } from "../../lib/mail/mailer";
import { resetPasswordEmail, verifyEmail } from "../../lib/mail/templates";

export type AuthOptions = {
  secret: string;
  baseURL: string;
  /** Sends the reset and verification emails. */
  mailer: Mailer;
  /** Keeps an email send alive after the response is out, so it never delays the reply. Workers' `waitUntil`. */
  runInBackground?: (task: Promise<unknown>) => void;
  /** Runs before an account is deleted, such as removing its stored files. If it throws, the account stays. */
  beforeDeleteUser?: (userId: string) => Promise<void>;
};

/**
 * Better Auth's settings, without the database. `createAuth` adds Drizzle; tests add a memory adapter.
 *
 * The iOS app keeps no cookies, so the bearer plugin hands back a session token on sign-in
 * (in the `set-auth-token` header) and accepts it as `Authorization: Bearer <token>` afterwards.
 */
export function authOptions(options: AuthOptions) {
  const { mailer } = options;
  return {
    secret: options.secret,
    baseURL: options.baseURL,
    emailAndPassword: {
      enabled: true,
      minPasswordLength: 8,
      // Sign-up signs you straight in. Verifying the email is asked for, not required.
      autoSignIn: true,
      requireEmailVerification: false,
      // Whoever reset the password should be the only one still signed in.
      revokeSessionsOnPasswordReset: true,
      sendResetPassword: async ({ user, url }) => {
        await mailer.send({ to: user.email, ...resetPasswordEmail({ name: user.name, url }) });
      },
    },
    emailVerification: {
      sendOnSignUp: true,
      sendVerificationEmail: async ({ user, url }) => {
        await mailer.send({ to: user.email, ...verifyEmail({ name: user.name, url }) });
      },
    },
    user: {
      // Lets someone delete their own account from the profile screen, confirmed with their password.
      deleteUser: {
        enabled: true,
        beforeDelete: async (user) => {
          await options.beforeDeleteUser?.(user.id);
        },
      },
    },
    session: {
      // A phone stays signed in for 90 days, and each use within that time pushes it back.
      expiresIn: 60 * 60 * 24 * 90,
      updateAge: 60 * 60 * 24,
    },
    advanced: options.runInBackground ? { backgroundTasks: { handler: options.runInBackground } } : {},
    plugins: [bearer()],
  } satisfies BetterAuthOptions;
}

/** Better Auth for email and password sign-in, on the request's database. */
export function createAuth(db: Db, options: AuthOptions) {
  return betterAuth({ ...authOptions(options), database: drizzleAdapter(db, { provider: "pg", schema }) });
}

export type Auth = ReturnType<typeof createAuth>;
export type Session = Auth["$Infer"]["Session"];
