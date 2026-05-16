# Claude context — vanducvt0305/fleet fork

This is **vanducvt0305's fork** of [fleetdm/fleet](https://github.com/fleetdm/fleet)
for self-hosting **Fleet Free** with custom additions.

**Always read `FORK.md` first** — it has the canonical setup, secret list,
deploy steps, and CI/CD layout. This file is the lightweight "what state
is this repo in" briefing.

## What's already done

- Forked `fleetdm/fleet` → `github.com/vanducvt0305/fleet`
- Fork-specific CI/CD added in `.github/workflows/`:
  - `ci-pr.yml` — lint + smoke build on PRs
  - `docker-build.yml` — build & push image to `ghcr.io/vanducvt0305/fleet` on push to main / tag `v*` / manual
  - `deploy-vps.yml` — manual-only SSH deploy to VPS (auto-trigger commented out until first manual run succeeds)
  - `sync-upstream.yml` — weekly Mon 03:00 UTC cron to PR upstream into fork
- `scripts/fork-disable-noise.sh` disabled 94 upstream Fleet-Inc-only workflows (dogfood, TUF, release pipelines, codesigning) — keep enabled: my 4 + CodeQL + Dependency Review + Scorecards
- Production deploy stack in `deploy/production/`: MySQL 8, Redis 7, Fleet, Caddy (auto Let's Encrypt)
- Docker image was built and pushed: `ghcr.io/vanducvt0305/fleet:latest` (verified working)

## User preferences

- Communicates in **Vietnamese** — respond in Vietnamese unless asked otherwise.
- Uses **Fleet Free tier intentionally** — never enable Premium features (`--dev_license`, `ee/` code paths, `FLEET_LICENSE_KEY`). The whole point of the fork is to extend the free tier.
- GitHub account: `vanducvt0305` (email `vanducvt0305@gmail.com`).
- Likes terse, opinionated answers with reasoning ("vì sao"). Avoid generic enumerations.

## Common operations

```bash
# Check fork CI status
gh run list -R vanducvt0305/fleet -L 10

# Trigger manual deploy
gh workflow run "Deploy to VPS" -R vanducvt0305/fleet

# Trigger manual image build
gh workflow run "Build & Push Docker image" -R vanducvt0305/fleet

# Re-run disable-noise after upstream sync (in case new workflows landed)
./scripts/fork-disable-noise.sh
```

## What to NOT do without asking

- Don't enable Premium / `ee/` features.
- Don't push to `main` without explicit confirmation — open a feature branch and PR.
- Don't run destructive ops on the VPS DB (`drop database`, hard reset migrations, etc.) without confirmation.
- Don't re-enable upstream Fleet-Inc workflows (dogfood, TUF, release-*) — they fail without Fleet Inc secrets and spam notifications.

## Local dev

See `FORK.md` § "Local development". Requires Go (per `go.mod`), Node `24.10.0`
(`.nvmrc` is set), Yarn `1.22.x`, Docker.

## Where things live

| Topic | File |
|---|---|
| Fork setup & secret list | `FORK.md` |
| CI/CD workflows | `.github/workflows/{ci-pr,docker-build,sync-upstream,deploy-vps}.yml` |
| Production compose + Caddy | `deploy/production/` |
| Disable-noise script | `scripts/fork-disable-noise.sh` |
| Upstream Fleet docs | `docs/` (kept in sync via `sync-upstream.yml`) |
