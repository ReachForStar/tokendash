# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, Codex, etc.) when working with code in this repository.

## Commands

```bash
npm run dev          # Start both server (tsx watch) and client (vite) concurrently
npm run build        # Build frontend (vite build) + server (tsc)
npm run typecheck    # Type-check both server and frontend without emitting
npm test             # Run unit tests (vitest)
npm run test:e2e     # Run e2e tests (playwright)
npm run start        # Run production build
```

Run a single unit test: `npx vitest run src/path/to.test.ts`
Run a single e2e test: `npx playwright test -g "test name pattern"`

## Architecture

Three-tier app: **Express server** parses local AI assistant data files and serves JSON APIs; **React frontend** (Vite + Tailwind + Recharts) renders dashboards; **shared types** connect them.

### Multi-Agent Parser Pattern

Each supported AI coding assistant has a parser module in `src/server/`:

| Agent | Parser | Data Source | Analytics |
|---|---|---|---|
| Claude Code | `claudeJsonlParser.ts` + `claudeBlocksParser.ts` | `~/.claude/projects/` JSONL | Yes |
| Codex | `codexParser.ts` | `~/.codex/sessions/` | No |
| OpenClaw | `openclawParser.ts` | `~/.openclaw/sessions/` | Yes |
| OpenCode | `opencodeParser.ts` | `~/.local/share/opencode/opencode.db` (SQLite) | No |

Every parser exports the same interface: `getDailyResponse()`, `getProjectsResponse()`, `getBlocksResponse()`. Detection functions live in `agentDetection.ts`.

Adding a new agent requires: parser module → detection function → route dispatch in `daily.ts`/`projects.ts`/`blocks.ts`/`analytics.ts` → agent button in `Dashboard.tsx`.

### API Routes

All endpoints in `src/server/routes/` follow the same pattern: check cache → stale-while-revalidate → parse → validate with Zod schema (`src/shared/schemas.ts`) → respond.

### Frontend Data Flow

`Dashboard.tsx` fetches 4 endpoints (`daily`, `projects`, `blocks`, `analytics`) via `useCcusageData` hook. `filteredDaily` prefers `projectsData` (per-model breakdowns) over `dailyData` (aggregated totals). Time range and project filtering happen client-side via `filterProjectDaily()` and `filterByTime()`.

## E2E Testing Strategy

E2E tests use `page.route()` to intercept all `/api/*` calls and return deterministic fixture data from `e2e/fixtures.ts`. Dates are generated relative to `Date.now()` so "Today" tests always work. No real data files needed — tests run on any machine or CI.

Playwright config uses `vite preview` (port 3457) to serve the built frontend, with `CI=true` preventing server reuse.

## Stability Rules

- **Bug fix / small change**: must pass `npm test` (unit tests) before committing
- **Larger change** (new agent, route logic, Dashboard rendering): must pass `npm run test:e2e` (e2e tests) before committing
- **PR submission**: CI runs both `npm test` and `npm run test:e2e` automatically

## Release Checklist

For every release:

1. Update `package.json`, `package-lock.json`, and `CHANGELOG.md`.
2. Run `npm run deploy:check`.
3. Commit and push the complete release candidate to `main`.
4. Run `npm run deploy` to publish npm, the git tag, DMG, appcast, and GitHub Release together.

Do not publish npm or create the GitHub Release manually; the unified deploy
script enforces the paired DMG/appcast requirement for Sparkle updates.

## Branch Workflow

The repository uses a two-branch model: `main` (stable, releasable) and `develop` (integration for in-progress work).

- `main` is the only branch that may be released. It must always build and pass tests.
- `develop` is the default working branch. All new features and fixes land here first.
- Do not commit directly to `main` except for fast-forward merges from `develop` or hotfixes that are immediately merged back.

### Starting a task

1. Ensure `develop` is up to date with `main`:
   ```bash
   git checkout main && git pull
   git checkout develop && git pull
   git merge main   # only if develop lags behind main
   ```
2. Branch short-lived work off `develop` when needed (`git checkout -b feat/xxx develop`), or commit directly on `develop` for small changes.

### Completing a task

1. Run the relevant tests (`npm test` for small changes, `npm run test:e2e` for larger ones) and fix all failures.
2. Commit on `develop` and push.
3. Merge `develop` into `main` after the task is verified:
   ```bash
   git checkout main && git merge develop && git push
   ```
4. Delete merged feature branches. Keep only `main` and `develop` long-term.

### Branch hygiene

- Before merging any feature branch into `develop`, first merge the current `develop` (or `main`) into that branch so it stays reconciled with the latest code.
- Delete stale or already-merged branches after inspecting them; do not accumulate dead branches.
- Never force-push `main` or `develop`. Rebase only local unshared branches.
- Release commits and tags are produced only from `main` per the Release Checklist above.
