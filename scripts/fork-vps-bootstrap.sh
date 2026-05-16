#!/usr/bin/env bash
# Bootstrap a fresh VPS to host Fleet via the fork's CI/CD pipeline.
#
# Run as root on a fresh Ubuntu host:
#   curl -fsSL https://raw.githubusercontent.com/vanducvt0305/fleet/main/scripts/fork-vps-bootstrap.sh | sudo bash
# Or pass the domain inline (otherwise FLEET_DOMAIN is left blank in the secrets file):
#   curl -fsSL ...bootstrap.sh | sudo FLEET_DOMAIN=fleet.example.com bash
#
# What this does:
#   1. apt install docker.io + docker-compose-v2 + ufw
#   2. Create user `deploy` (uid auto), add to docker group
#   3. Generate ed25519 SSH key for deploy, append pubkey to authorized_keys
#   4. ufw allow 22/80/443/tcp, enable
#   5. mkdir -p /srv/fleet, chown deploy
#   6. Generate 3 random secrets (MYSQL_PASSWORD, MYSQL_ROOT_PASSWORD, FLEET_AUTH_JWT_KEY)
#   7. Write all 10 GitHub Environment secrets to /root/fleet-secrets.txt (chmod 600)
#
# Idempotent: re-running aborts if /root/fleet-secrets.txt already exists, to avoid
# rotating secrets that are already wired into GitHub. Delete that file first to redo.

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Must run as root (try: sudo $0)" >&2
  exit 1
fi

if ! grep -qE '^(NAME|ID)=.*[Uu]buntu' /etc/os-release; then
  echo "This script targets Ubuntu. Detected:" >&2
  grep -E '^(NAME|VERSION)=' /etc/os-release >&2 || true
  echo "Adapt apt/ufw commands for your distro before running." >&2
  exit 1
fi

SECRETS_FILE=/root/fleet-secrets.txt
if [ -e "$SECRETS_FILE" ]; then
  echo "Refusing to overwrite existing $SECRETS_FILE (would rotate secrets)." >&2
  echo "If you really want to regenerate from scratch, delete it and re-run." >&2
  exit 1
fi

DEPLOY_DIR=/srv/fleet
DEPLOY_USER=deploy
FLEET_DOMAIN=${FLEET_DOMAIN:-}

echo "==> 1/7 apt update + install docker, ufw"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq docker.io docker-compose-v2 ufw openssl

echo "==> 2/7 create user $DEPLOY_USER + add to docker group"
if id "$DEPLOY_USER" >/dev/null 2>&1; then
  echo "user $DEPLOY_USER already exists, skipping create"
else
  adduser --disabled-password --gecos "" "$DEPLOY_USER"
fi
usermod -aG docker "$DEPLOY_USER"

echo "==> 3/7 generate SSH key for GitHub Actions deploy"
sudo -u "$DEPLOY_USER" bash <<'INNER'
set -euo pipefail
mkdir -p ~/.ssh
chmod 700 ~/.ssh
if [ ! -f ~/.ssh/fleet-deploy ]; then
  ssh-keygen -t ed25519 -f ~/.ssh/fleet-deploy -N "" -C "github-actions-deploy" -q
fi
PUB=$(cat ~/.ssh/fleet-deploy.pub)
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
grep -qxF "$PUB" ~/.ssh/authorized_keys || echo "$PUB" >> ~/.ssh/authorized_keys
INNER

echo "==> 4/7 firewall (ufw allow 22/80/443)"
ufw allow 22/tcp >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw --force enable >/dev/null

echo "==> 5/7 create deploy directory $DEPLOY_DIR"
mkdir -p "$DEPLOY_DIR"
chown "$DEPLOY_USER:$DEPLOY_USER" "$DEPLOY_DIR"

echo "==> 6/7 generate strong random secrets"
MYSQL_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')
FLEET_AUTH_JWT_KEY=$(openssl rand -base64 32 | tr -d '\n')
# Required by Fleet for MDM features — encrypts APNs/SCEP/BM secrets in DB.
# Rotating this key requires a Fleet-documented migration; treat as permanent.
FLEET_SERVER_PRIVATE_KEY=$(openssl rand -base64 32 | tr -d '\n')

echo "==> 7/7 collect VPS info + write $SECRETS_FILE"
VPS_HOST=$(curl -fs4 https://ifconfig.me 2>/dev/null \
  || curl -fs4 https://icanhazip.com 2>/dev/null \
  || hostname -I | awk '{print $1}')
PRIVATE_KEY=$(sudo -u "$DEPLOY_USER" cat ~deploy/.ssh/fleet-deploy)

umask 077
cat > "$SECRETS_FILE" <<EOF
==== GitHub Environment Secrets (paste into the 'production' environment) ====
Settings → Environments → production → Add secret (one per line below)

VPS_HOST=$VPS_HOST
VPS_USER=$DEPLOY_USER
VPS_PORT=22
VPS_DEPLOY_DIR=$DEPLOY_DIR
FLEET_DOMAIN=${FLEET_DOMAIN:-<FILL: your.domain.example.com>}
MYSQL_PASSWORD=$MYSQL_PASSWORD
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
FLEET_AUTH_JWT_KEY=$FLEET_AUTH_JWT_KEY
FLEET_SERVER_PRIVATE_KEY=$FLEET_SERVER_PRIVATE_KEY

==== VPS_SSH_KEY (paste the entire block below, including BEGIN/END lines) ====
$PRIVATE_KEY

==== Next steps ====
1. Point your domain's A record at $VPS_HOST and wait until DNS resolves.
2. Create GitHub environment 'production':
   https://github.com/vanducvt0305/fleet/settings/environments
3. Add the 10 secrets above (VPS_HOST … VPS_SSH_KEY).
4. Trigger 'Build & Push Docker image' workflow once (manual run) to seed GHCR.
5. Trigger 'Deploy to VPS' workflow. After it goes green and you've confirmed
   the secrets are saved in GitHub, securely delete this file:
     shred -u $SECRETS_FILE ~$DEPLOY_USER/.ssh/fleet-deploy ~$DEPLOY_USER/.ssh/fleet-deploy.pub
EOF
chmod 600 "$SECRETS_FILE"

echo
echo "==== BOOTSTRAP COMPLETE ===="
echo "Secrets written to $SECRETS_FILE (chmod 600). cat it to copy into GitHub."
echo "VPS IP: $VPS_HOST"
[ -n "$FLEET_DOMAIN" ] && echo "FLEET_DOMAIN: $FLEET_DOMAIN"
