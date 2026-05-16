# Fork notes

This is a fork of [fleetdm/fleet](https://github.com/fleetdm/fleet) for
running Fleet **Free** with custom additions. The notes below are specific
to this fork — see upstream docs for everything else.

## Local development

Prerequisites match upstream: Go (per `go.mod`), Node `24.10.0` (via `nvm` —
`.nvmrc` is in the repo), Yarn `1.22.x` (via `corepack`), Docker.

```bash
nvm use                          # picks up .nvmrc
make deps && make generate && make
docker compose up -d
./build/fleet prepare db --dev
FLEET_SERVER_ADDRESS=0.0.0.0:8088 ./build/fleet serve --dev
```

> Run on `:8088` not `:8080` if you have other services bound to 8080.

## CI/CD overview

Four workflows live in `.github/workflows/`:

| File | Trigger | Purpose |
|---|---|---|
| `ci-pr.yml` | PR to `main` | golangci-lint, `go vet`/`gofmt`, `yarn lint`, smoke `go build` |
| `docker-build.yml` | push `main`, tag `v*`, manual | Builds Fleet binary + Docker image, pushes to `ghcr.io/<owner>/fleet` |
| `deploy-vps.yml` | After `docker-build` succeeds on `main`, or manual | SSH into VPS, pull image, run migrations, restart compose |
| `sync-upstream.yml` | Weekly cron + manual | Auto-PR from `fleetdm/fleet:main` into fork |

All other upstream workflows are disabled by `scripts/fork-disable-noise.sh`
because they target Fleet Inc's internal infra (dogfood, TUF, codesigning,
release pipelines) and would fail or spam noise on a fork.

### One-time setup after fork

```bash
# Disable upstream Fleet-Inc-only workflows
./scripts/fork-disable-noise.sh
```

Re-run after each upstream sync if a new noise workflow lands.

### Secrets required

Add these in GitHub → repo Settings → Secrets and variables → Actions.

**For deploy-vps.yml (Environment: `production`):**

| Secret | Example | Notes |
|---|---|---|
| `VPS_HOST` | `1.2.3.4` or `fleet.example.com` | SSH target |
| `VPS_USER` | `deploy` | non-root user with docker access |
| `VPS_PORT` | `22` | optional, defaults to 22 |
| `VPS_SSH_KEY` | private key contents | generated via `ssh-keygen -t ed25519`, public key on VPS `~/.ssh/authorized_keys` |
| `VPS_DEPLOY_DIR` | `/srv/fleet` | where compose files live on VPS |
| `FLEET_DOMAIN` | `fleet.yourdomain.com` | Caddy will auto-provision Let's Encrypt cert |
| `MYSQL_PASSWORD` | random 32+ chars | for `fleet` MySQL user |
| `MYSQL_ROOT_PASSWORD` | random 32+ chars | for MySQL root |
| `FLEET_AUTH_JWT_KEY` | random 32+ chars | session signing key |
| `FLEET_SERVER_PRIVATE_KEY` | random 32+ bytes (base64) | required for MDM — encrypts APNs/SCEP/BM secrets at rest. Treat as permanent: rotating needs a Fleet-documented migration |

Generate strong values:
```bash
openssl rand -base64 32   # for each password / jwt key
```

### VPS prerequisites

Use `scripts/fork-vps-bootstrap.sh` to set everything up on a fresh
Ubuntu host (installs Docker, creates `deploy` user, generates the SSH
key + secrets, opens ports 22/80/443):

```bash
curl -fsSL https://raw.githubusercontent.com/vanducvt0305/fleet/main/scripts/fork-vps-bootstrap.sh \
  | sudo FLEET_DOMAIN=fleet.example.com bash
```

It writes all 10 GitHub secrets (above) to `/root/fleet-secrets.txt`
(chmod 600). Paste them into the `production` environment, then run
`Build & Push Docker image` once, then `Deploy to VPS`. After confirming
secrets are saved on GitHub, `shred -u /root/fleet-secrets.txt ~deploy/.ssh/fleet-deploy*`.

Point `A` record of `FLEET_DOMAIN` to the VPS IP before triggering deploy.
Caddy gets a Let's Encrypt cert on first start (HTTP-01 needs port 80
reachable + DNS resolving).

## Image registry

Images are pushed to **GHCR**: `ghcr.io/<your-github-user>/fleet`.

By default GHCR images are **private** when pushed by a private user repo.
To pull from the VPS, the deploy workflow does `docker login ghcr.io`
with `GITHUB_TOKEN`. If you'd rather make images public, go to
Packages → fleet → Settings → Change visibility.

## Sync from upstream

The weekly job opens a PR `sync/upstream-YYYYMMDD` against `main`. Review
the diff, run `./scripts/fork-disable-noise.sh` if upstream added new noise
workflows, then merge. On merge conflicts, the branch is hard-reset to
upstream — review carefully and re-apply fork-only changes manually.

## Customizing

Fork-only code goes in any directory; sync-upstream merges from
`fleetdm/fleet` so your changes survive as long as they don't touch the
same lines. Stable extension points:
- Add new Go packages anywhere — won't conflict with upstream
- Add new frontend pages under `frontend/pages/` — same
- Modify existing files: expect occasional conflicts during sync

## License

Fleet Free is MIT-licensed. The `ee/` directory contains Premium features
under a Business Source License — leave it alone if you don't have a
Premium license.
