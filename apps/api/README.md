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

| Variable               | What it is                                                                              | Where                                 |
| ---------------------- | --------------------------------------------------------------------------------------- | ------------------------------------- |
| `BETTER_AUTH_URL`      | The public URL of the API. Every link in an email starts with it.                       | `wrangler secret put`, `.env` locally |
| `RESEND_API_KEY`       | Resend API key. Unset means emails go to the console.                                   | `wrangler secret put RESEND_API_KEY`  |
| `EMAIL_FROM`           | Sender, such as `Fatigue <no-reply@yourdomain>`. The domain must be verified in Resend. | `wrangler.jsonc` vars, `.env` locally |
| `APP_DEEP_LINK_SCHEME` | The iOS app's URL scheme. Defaults to `fatigue`, which matches the app.                 | `wrangler.jsonc` vars                 |

## Profiles and friends

Every route here needs `Authorization: Bearer <token>`. The design is on the Social docs page.

- `GET /api/profiles/me` is your profile, or 404 with `no_profile` until you've picked a handle.
- `PUT /api/profiles/me` with `{ handle?, bio?, defaultVisibility? }` creates or changes it. A handle is needed the first time. Handles are stored lowercase, 3 to 20 of `a-z`, `0-9`, `_` and `.`, and a leading `@` is dropped. A taken handle is 409 `handle_taken`.
- `GET /api/profiles/search?q=` finds up to 20 people whose handle starts with `q`.
- `GET /api/profiles/:handle` is someone's profile. Each person comes with `relation`: `self`, `friends`, `incoming`, `outgoing` or `none`.
- `GET /api/friends` lists friends, then requests to you, then requests you sent.
- `POST /api/friends/:userId` sends a request. If they already asked you, it accepts theirs.
- `POST /api/friends/:userId/accept` accepts their request.
- `DELETE /api/friends/:userId` declines, takes back a request, or unfriends. The row is deleted, so either person can ask again.

### Shared workouts

- `PUT /api/posts/:id` with `{ workoutId, caption?, visibility?, startedAt, snapshotVersion, snapshot }` shares a workout. The phone makes the ID, so sending the same share twice updates one post. Sharing a workout that already has a live post replaces its snapshot and keeps the first post's ID, which comes back in the response. `visibility` defaults to the profile's. A deleted post's ID is refused with 410.
- `GET /api/posts/feed?cursor=` is your posts and your accepted friends' public and friends only posts, newest workout first, 20 a page. Pass the response's `nextCursor` for the next page; it's null on the last.
- `GET /api/posts/by/:userId?cursor=` is someone's posts that you can see: all of yours, their public ones, and their friends only ones if you're friends.
- `GET /api/posts/:id` is one post, or 404 if you can't see it.
- `DELETE /api/posts/:id` deletes your post.

The snapshot is stored as it comes, up to 256 KB. The server never reads inside it; `workoutId` is only sent back to the sharer.

Service tests run against PGlite, a Postgres that runs in memory, with every migration applied (`src/db/test-db.ts`). They need no database running.

## Deploying

1. Verify a sending domain in Resend and create an API key.
2. Set `EMAIL_FROM` in `wrangler.jsonc` to the verified sender. `BETTER_AUTH_URL` is a secret, set in the deploy steps below.
3. `wrangler secret put DATABASE_URL`, `wrangler secret put BETTER_AUTH_SECRET`, `wrangler secret put RESEND_API_KEY`.
4. `pnpm --filter @fatigue/api deploy`, then point `APIConfig.baseURL` in the iOS app at the deployed URL.

## Changing the Better Auth config

Better Auth's tables in `src/db/schema/auth.ts` are generated. After changing its config in `src/modules/auth/auth.ts`, run `pnpm --filter @fatigue/api auth:schema`, then `pnpm --filter @fatigue/api db:generate` to write the migration.

## Deploying

The API runs as the `fatigue-api` Worker on Cloudflare Workers (paid plan), against a Postgres on Neon. `.github/workflows/deploy-api.yml` deploys it on every push to `main` that touches `apps/api`, and can be run by hand from the Actions tab. Each deploy type checks, tests, runs the migrations against production, then uploads the Worker and checks `/health`.

Local dev is untouched by any of this: `.env` and your dev Neon branch (or Docker) stay as they are. Only `wrangler deploy` and the workflow reach production.

### One-time setup

Do this once, from `apps/api`, signed in to Cloudflare with `pnpm exec wrangler login`.

1. **Neon production branch.** In the Neon project, create a branch named `production` from `main` (Branches → Create branch, or `neon branches create --name production`). Copy two connection strings from Connect: the **pooled** one (toggle "Connection pooling"; the host contains `-pooler`) for the Worker, which opens a connection per request, and the **direct** one for migrations, which Neon recommends running outside the pooler.

2. **Deploy the Worker once by hand** so it exists before secrets go on it:

   ```sh
   pnpm exec wrangler deploy
   ```

   The output ends with the public URL, `https://fatigue-api.<subdomain>.workers.dev`. Keep it.

3. **Worker secrets.** Each command prompts for the value; nothing is written to disk.

   ```sh
   pnpm exec wrangler secret put DATABASE_URL        # the Neon production pooled URL
   pnpm exec wrangler secret put BETTER_AUTH_SECRET  # paste the output of: openssl rand -base64 32
   pnpm exec wrangler secret put BETTER_AUTH_URL     # the Worker URL from step 2, no trailing slash
   ```

   `BETTER_AUTH_SECRET` must be a new value, not the one in your `.env`. `BETTER_AUTH_URL` must be exactly the URL the app calls, or Better Auth refuses sign-in.

4. **GitHub secrets** (repository Settings → Secrets and variables → Actions). Put them in a `production` environment if you want to approve deploys; the workflow uses that environment name.

   | Secret                  | Value                                                                                                                         |
   | ----------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
   | `CLOUDFLARE_API_TOKEN`  | Cloudflare dashboard → My Profile → API Tokens → Create Token → "Edit Cloudflare Workers" template. Scope it to this account. |
   | `CLOUDFLARE_ACCOUNT_ID` | Workers & Pages overview, right-hand column.                                                                                  |
   | `DATABASE_URL`          | The Neon production **direct** URL. The workflow uses it to run migrations.                                                   |

5. **Point the app at it.** Set `APIConfig.productionBaseURL` in `apps/ios/Fatigue/Auth/AuthAPI.swift` to the Worker URL. Debug builds keep using localhost.

6. Run the workflow once from the Actions tab (Deploy API → Run workflow) to confirm the whole path works, then it runs on its own.

### Migrations

`pnpm api:migrate` (`drizzle-kit migrate`) applies `src/db/migrations` to whatever `DATABASE_URL` points at. Locally that comes from `.env`; in the workflow it comes from the `DATABASE_URL` GitHub secret. Drizzle records applied migrations in `drizzle.__drizzle_migrations`, so re-running is a no-op.

Migrations run before the Worker uploads, so new code never meets an old schema. Keep migrations additive (add tables and nullable columns, don't drop or rename in the same release) and the previous version keeps working during the few seconds between the two steps. If a migration fails the Worker is not deployed; fix the migration and re-run the workflow.

To run a migration against production by hand, for example to catch up a fresh branch:

```sh
DATABASE_URL='postgres://...neon.tech/neondb?sslmode=require' pnpm api:migrate
```

### Checking a deploy

- `curl https://fatigue-api.<subdomain>.workers.dev/health` answers `{"ok":true}`.
- `pnpm exec wrangler secret list` shows `DATABASE_URL`, `BETTER_AUTH_SECRET` and `BETTER_AUTH_URL`.
- `pnpm exec wrangler tail` streams live requests; the dashboard's Logs tab keeps them (observability is on in `wrangler.jsonc`).
- From a TestFlight build on a real phone: sign up with a new email, sign out, sign in again, then delete the account from the profile screen. Each step should succeed, and the row should be gone from `user` in the Neon production branch afterwards.
- The Neon production branch shows the tables from `src/db/migrations` and a `drizzle.__drizzle_migrations` row per migration.

### Changing the URL later

A custom domain is a one-line `routes` entry in `wrangler.jsonc` plus updating `BETTER_AUTH_URL` (`wrangler secret put` again) and `APIConfig.productionBaseURL`. Ship the app update and the Worker change together, since release builds only know one URL.
