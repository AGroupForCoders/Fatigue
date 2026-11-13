# Fatigue

A weightlifting tracker that knows which machine you used. History and records are kept per machine brand, and custom exercises are unlimited.

The repository holds the iOS app (`apps/ios`), the API (`apps/api`), the shared design tokens (`packages/tokens`) and the documentation site (`apps/docs`). The iOS app logs workouts, keeps history and records per brand and stores everything in SQLite on the phone. The API signs people in. Sync and the App Store work are still to come.

## Read the docs

```bash
pnpm install
pnpm docs:dev
```

Then open http://localhost:3000. You need Node 22 or newer and pnpm. The docs cover the MVP, requirements, scores and stats, data model, tech stack, repository layout, API structure, CI plan and design system.

## Run the app

- **iOS:** open `apps/ios/Fatigue.xcodeproj` in Xcode and run the Fatigue scheme. Debug builds look for the API at http://localhost:8787.
- **API:** `apps/api/README.md` has the steps. In short, start a Postgres, copy `.env.example` to `.env`, then `pnpm api:migrate` and `pnpm api:dev`.
- **Tokens:** edit `packages/tokens/tokens.json`, then `pnpm tokens:build` and commit the generated `Tokens.swift`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for branch names, the commit format and how pull requests are merged.
