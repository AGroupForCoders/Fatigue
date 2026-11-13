# Contributing

The [contributing page in the docs](apps/docs/content/docs/contributing.mdx) has the same rules with more examples.

## Branching

Always branch off `main`. Never commit directly to `main`.

| Type     | Pattern           | Example                 |
| -------- | ----------------- | ----------------------- |
| Feature  | `feat/<name>`     | `feat/machine-variants` |
| Bug fix  | `fix/<name>`      | `fix/rest-timer-reset`  |
| Refactor | `refactor/<name>` | `refactor/sync-queue`   |
| Docs     | `docs/<name>`     | `docs/api-structure`    |
| Chore    | `chore/<name>`    | `chore/update-deps`     |

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/) with a scope:

```
<type>(<scope>): <description>
```

Types: `feat`, `fix`, `refactor`, `perf`, `style`, `test`, `docs`, `chore`, `ci`, `revert`

Scopes say which part of the monorepo the commit changes:

| Scope      | Covers                                                      |
| ---------- | ----------------------------------------------------------- |
| `ios`      | `apps/ios`                                                  |
| `android`  | `apps/android`                                              |
| `web`      | `apps/web`                                                  |
| `api`      | `apps/api`                                                  |
| `docs`     | `apps/docs`                                                 |
| `contract` | `packages/contract`                                         |
| `ci`       | `.github/workflows`                                         |
| `repo`     | Root config, templates and anything spanning the repository |

Examples:

```
feat(ios): add rest timer to the workout screen
fix(api): reject sync pushes with a missing row id
chore(repo): add issue templates
```

- Lowercase, imperative mood, no full stop
- Max 72 characters
- Breaking changes: add `!` after the scope, e.g. `feat(api)!: change the sync cursor format`
- If a change spans two apps, split it into one commit per app where you can

## Pull requests

- One concern per PR. Don't mix features with refactors
- The PR title follows the same commit format, scope included
- All PRs are squash merged, so your branch commits become one commit on `main`
- Delete the branch after merging

## Local development

You need Node 22 or newer and pnpm for the TypeScript projects, and Xcode for the iOS app.

```bash
pnpm install
pnpm docs:dev        # docs at http://localhost:3000
pnpm docs:build      # check the docs build, with pnpm docs:types for the types
pnpm api:dev         # API at http://localhost:8787, see apps/api/README.md for Postgres and .env
pnpm api:test        # API tests
pnpm tokens:build    # regenerate apps/ios/Fatigue/DesignSystem/Tokens.swift from tokens.json
pnpm tokens:check    # fails if the generated file is out of date
```

The iOS app is not part of the pnpm workspace. Open `apps/ios/Fatigue.xcodeproj` in Xcode and run the Fatigue scheme, or run the tests with ⌘U.
