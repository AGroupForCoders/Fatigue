import type { Db } from "./db/client";
import type { Bindings } from "./env";
import type { Auth, Session } from "./modules/auth/auth";

/** What every route can read from the Hono context. */
export type AppEnv = {
  Bindings: Bindings;
  Variables: {
    db: Db;
    auth: Auth;
    session: Session | null;
  };
};
