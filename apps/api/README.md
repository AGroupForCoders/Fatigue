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

### Password reset and email verification

Both are Better Auth's own flows, with the emails sent through [Resend](https://resend.com):

- `POST /api/auth/request-password-reset` with `{ email, redirectTo }` emails a link. Better Auth checks the token at `GET /api/auth/reset-password/:token` and redirects to `redirectTo` with `?token=`; the app sends `redirectTo` as `<BETTER_AUTH_URL>/auth/reset-password`, a small page in `src/modules/auth/auth.pages.ts` that opens the app at `fatigue://reset-password?token=…`. The app then calls `POST /api/auth/reset-password` with `{ token, newPassword }`. Resetting signs out every other device.
- Sign-up sends a verification email (`emailVerification.sendOnSignUp`). You can use the app before verifying; `requireEmailVerification` is off. The link lands on `GET /api/auth/verify-email`, which redirects to the `callbackURL` the app sent, `<BETTER_AUTH_URL>/auth/email-verified`, and that page opens the app at `fatigue://email-verified`. Settings can ask for another email with `POST /api/auth/send-verification-email`.
- Emails are built in `src/lib/mail/templates.ts` and sent by `src/lib/mail/mailer.ts`. Without `RESEND_API_KEY` they're printed to the Wrangler log instead, link included, so nothing else is needed locally.

Settings:

| Variable | What it is | Where |
| --- | --- | --- |
| `BETTER_AUTH_URL` | The public URL of the API. Every link in an email starts with it. | `wrangler.jsonc` vars, `.env` locally |
| `RESEND_API_KEY` | Resend API key. Unset means emails go to the console. | `wrangler secret put RESEND_API_KEY` |
| `EMAIL_FROM` | Sender, such as `Fatigue <no-reply@yourdomain>`. The domain must be verified in Resend. | `wrangler.jsonc` vars, `.env` locally |
| `APP_DEEP_LINK_SCHEME` | The iOS app's URL scheme. Defaults to `fatigue`, which matches the app. | `wrangler.jsonc` vars |

## Deploying

1. Verify a sending domain in Resend and create an API key.
2. Set `BETTER_AUTH_URL` and `EMAIL_FROM` in `wrangler.jsonc` to the deployed URL and the verified sender.
3. `wrangler secret put DATABASE_URL`, `wrangler secret put BETTER_AUTH_SECRET`, `wrangler secret put RESEND_API_KEY`.
4. `pnpm --filter @fatigue/api deploy`, then point `APIConfig.baseURL` in the iOS app at the deployed URL.

## Changing the Better Auth config

Better Auth's tables in `src/db/schema/auth.ts` are generated. After changing its config in `src/modules/auth/auth.ts`, run `pnpm --filter @fatigue/api auth:schema`, then `pnpm --filter @fatigue/api db:generate` to write the migration.
