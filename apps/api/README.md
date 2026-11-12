# Fatigue API

Hono on Cloudflare Workers, with Better Auth for accounts and Drizzle over Postgres.

## Running it locally

1. Start a Postgres. Docker is the quickest:

   ```sh
   docker run -d --name fatigue-postgres -e POSTGRES_USER=fatigue -e POSTGRES_PASSWORD=fatigue -e POSTGRES_DB=fatigue -p 5432:5432 postgres:17
   ```

2. Copy `.env.example` to `.env` and set `BETTER_AUTH_SECRET` to the output of `openssl rand -base64 32`. Point `DATABASE_URL` at a Neon branch instead if you'd rather.
3. Create the tables with `pnpm api:migrate`.
4. Start the API with `pnpm api:dev`. It listens on http://localhost:8787, which is where debug builds of the iOS app look for it.

## Accounts

Sign-up, sign-in, sessions, renaming and deleting an account are Better Auth's own endpoints under `/api/auth`. The iOS app keeps no cookies: the session token comes back in the `set-auth-token` header and goes back as `Authorization: Bearer <token>`.

Better Auth's tables in `src/db/schema/auth.ts` are generated. After changing its config in `src/modules/auth/auth.ts`, run `pnpm --filter @fatigue/api auth:schema`, then `pnpm --filter @fatigue/api db:generate` to write the migration.
