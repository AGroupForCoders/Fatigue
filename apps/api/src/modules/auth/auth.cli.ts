// Only for `pnpm auth:schema`. The Better Auth CLI reads an `auth` export to work out which
// tables to generate. The real instance is built per request in auth.ts.
import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import { NoopMailer } from "../../lib/mail/mailer";
import { createAuth } from "./auth";

export const auth = createAuth(drizzle(postgres("postgres://localhost/unused")) as never, {
  secret: "unused-only-for-schema-generation",
  baseURL: "http://localhost",
  mailer: new NoopMailer(),
});
