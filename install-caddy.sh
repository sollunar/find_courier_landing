#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.caddy.yml"
readonly ENV_FILE="${SCRIPT_DIR}/.env.caddy"
readonly CONTAINER_NAME="findcourier-caddy"

DOMAIN=""
ACME_EMAIL=""
SELF_STEAL_PORT="11120"
OPEN_FIREWALL="false"

log() {
  printf '[find-courier-caddy] %s\n' "$*"
}

warn() {
  printf '[find-courier-caddy] WARNING: %s\n' "$*" >&2
}

die() {
  printf '[find-courier-caddy] ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  ./install-caddy.sh --domain DOMAIN --email EMAIL [options]

Required:
  --domain DOMAIN       Public camouflage hostname pointing to this node
  --email EMAIL         ACME account email used by Caddy

Options:
  --port PORT           Local Caddy HTTPS port (default: 11120)
  --open-firewall       Allow 80/tcp through UFW when UFW is active
  -h, --help            Show this help

Example:
  ./install-caddy.sh \
    --domain nl1.find-courier.com \
    --email admin@find-courier.com \
    --open-firewall

The script builds the React application into a Caddy image, starts Caddy on
127.0.0.1:11120, exposes only HTTP port 80 for ACME, waits for a valid public
certificate, and prints the matching Remnawave REALITY settings.
USAGE
}

while (($# > 0)); do
  case "$1" in
    --domain)
      (($# >= 2)) || die '--domain requires a value'
      DOMAIN="$2"
      shift 2
      ;;
    --email)
      (($# >= 2)) || die '--email requires a value'
      ACME_EMAIL="$2"
      shift 2
      ;;
    --port)
      (($# >= 2)) || die '--port requires a value'
      SELF_STEAL_PORT="$2"
      shift 2
      ;;
    --open-firewall)
      OPEN_FIREWALL="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "$DOMAIN" ]] || die '--domain is required'
[[ -n "$ACME_EMAIL" ]] || die '--email is required'

if [[ ! "$DOMAIN" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]; then
  die "invalid public domain: ${DOMAIN}"
fi

if [[ ! "$ACME_EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; then
  die "invalid ACME email: ${ACME_EMAIL}"
fi

if [[ ! "$SELF_STEAL_PORT" =~ ^[0-9]+$ ]] ||
  ((SELF_STEAL_PORT < 1024 || SELF_STEAL_PORT > 65535)); then
  die '--port must be an integer between 1024 and 65535'
fi

command -v docker >/dev/null 2>&1 ||
  die 'Docker is required. Install Remnawave Node/Docker first.'
docker compose version >/dev/null 2>&1 ||
  die 'Docker Compose v2 is required.'
command -v curl >/dev/null 2>&1 || die 'curl is required.'

if ! docker info >/dev/null 2>&1; then
  die 'cannot access the Docker daemon; run as root or grant Docker access'
fi

if command -v getent >/dev/null 2>&1; then
  mapfile -t resolved_ipv4 < <(
    getent ahostsv4 "$DOMAIN" | awk '{print $1}' | sort -u
  )

  if ((${#resolved_ipv4[@]} == 0)); then
    die "${DOMAIN} has no resolvable IPv4 A record"
  fi

  log "${DOMAIN} currently resolves to: ${resolved_ipv4[*]}"

  public_ipv4="$(curl -4fsS --connect-timeout 5 --max-time 10 https://api.ipify.org || true)"
  if [[ -n "$public_ipv4" ]]; then
    domain_points_here="false"
    for address in "${resolved_ipv4[@]}"; do
      if [[ "$address" == "$public_ipv4" ]]; then
        domain_points_here="true"
        break
      fi
    done

    if [[ "$domain_points_here" != "true" ]]; then
      die "${DOMAIN} does not resolve to this server's public IPv4 (${public_ipv4})"
    fi
  else
    warn 'could not determine this server public IPv4; DNS ownership was not verified'
  fi

  if getent ahostsv6 "$DOMAIN" >/dev/null 2>&1; then
    warn "${DOMAIN} has an AAAA record; ensure the Remnawave inbound also accepts IPv6 or remove it"
  fi
else
  warn 'getent is unavailable; DNS was not validated'
fi

port_owned_by_caddy() {
  docker ps --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"
}

port_is_listening() {
  local port="$1"

  if ! command -v ss >/dev/null 2>&1; then
    return 1
  fi

  ss -H -ltn | awk '{print $4}' | grep -Eq "(^|:|\\])${port}$"
}

if port_is_listening 80 && ! port_owned_by_caddy; then
  die 'port 80 is already occupied; Caddy needs it for ACME HTTP-01'
fi

if port_is_listening "$SELF_STEAL_PORT" && ! port_owned_by_caddy; then
  die "local target port ${SELF_STEAL_PORT} is already occupied"
fi

if [[ "$OPEN_FIREWALL" == "true" ]]; then
  if command -v ufw >/dev/null 2>&1 && ufw status | grep -q '^Status: active'; then
    log 'Allowing 80/tcp through UFW for ACME certificate issuance and renewal'
    ufw allow 80/tcp
  else
    warn 'UFW is unavailable or inactive; no firewall rules were changed'
  fi
fi

umask 077
env_tmp="$(mktemp "${SCRIPT_DIR}/.env.caddy.XXXXXX")"
cleanup() {
  rm -f -- "$env_tmp"
}
trap cleanup EXIT

printf 'SELF_STEAL_DOMAIN=%s\n' "$DOMAIN" >"$env_tmp"
printf 'SELF_STEAL_PORT=%s\n' "$SELF_STEAL_PORT" >>"$env_tmp"
printf 'ACME_EMAIL=%s\n' "$ACME_EMAIL" >>"$env_tmp"
mv -f -- "$env_tmp" "$ENV_FILE"
chmod 600 "$ENV_FILE"

compose() {
  CADDY_ENV_FILE="$ENV_FILE" docker compose \
    --project-directory "$SCRIPT_DIR" \
    -f "$COMPOSE_FILE" "$@"
}

log 'Validating Docker Compose configuration'
compose config --quiet

log 'Building the React application and Caddy image'
compose build --pull

log 'Starting the camouflage site'
compose up -d --remove-orphans

log 'Waiting for Caddy to obtain a public certificate'
site_ready="false"
for _ in $(seq 1 60); do
  if curl --fail --silent --show-error \
    --connect-timeout 3 \
    --max-time 5 \
    --resolve "${DOMAIN}:${SELF_STEAL_PORT}:127.0.0.1" \
    "https://${DOMAIN}:${SELF_STEAL_PORT}/" \
    --output /dev/null; then
    site_ready="true"
    break
  fi
  sleep 2
done

if [[ "$site_ready" != "true" ]]; then
  compose logs --tail=100 caddy-site >&2 || true
  die 'Caddy did not obtain a working certificate within 120 seconds'
fi

log 'Caddy camouflage site is ready'
compose ps

cat <<EOF

Use these values in the Remnawave inbound:

  "listen": "0.0.0.0",
  "port": 443,
  "streamSettings": {
    "network": "raw",
    "security": "reality",
    "realitySettings": {
      "target": "127.0.0.1:${SELF_STEAL_PORT}",
      "xver": 0,
      "serverNames": ["${DOMAIN}"],
      "privateKey": "GENERATE_A_NEW_UNIQUE_KEY",
      "shortIds": ["GENERATE_A_NEW_UNIQUE_SHORT_ID"]
    }
  }

Remnawave Host:
  Address: ${DOMAIN}
  Port:    443
  SNI:     ${DOMAIN}

After activating the inbound, verify from another machine:
  curl --fail --show-error https://${DOMAIN}/

The local target port ${SELF_STEAL_PORT} must remain closed to the internet.
EOF

