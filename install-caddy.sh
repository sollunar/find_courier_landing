#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.caddy.yml"
readonly ENV_FILE="${SCRIPT_DIR}/.env.caddy"
readonly CONTAINER_NAME='findcourier-caddy'
readonly CERT_ROOT='/opt/find-courier-camouflage/certs'

DOMAIN=''
CAMOUFLAGE_PORT='9443'
CLIENT_HOST=''
CERT_DIR=''

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
  ./install-caddy.sh --domain DOMAIN [options]

Required:
  --domain DOMAIN       Camouflage/SNI domain served by this node

Options:
  --port PORT           Loopback Caddy HTTPS port (default: 9443)
  --client-host HOST    Remnawave Host address shown to clients
                        (default: same as --domain)
  --cert-dir PATH       Directory containing fullchain.pem and privkey.pem
                        (default: /opt/find-courier-camouflage/certs/DOMAIN)
  -h, --help            Show this help

Example:
  ./install-caddy.sh \
    --domain nl.find-courier.com \
    --client-host nl.whopn.org \
    --cert-dir /opt/find-courier-camouflage/certs/nl.find-courier.com

This installer does not issue, renew, copy, or otherwise manage certificates.
The certificate and private key must already exist in --cert-dir. Caddy binds
only to 127.0.0.1:9443; Xray continues to own public port 443.
USAGE
}

validate_domain() {
  local value="$1"
  [[ "$value" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]] ||
    die "invalid domain: ${value}"
}

validate_absolute_path() {
  local value="$1"
  [[ "$value" =~ ^/[A-Za-z0-9._/-]+$ ]] || die "unsafe path: ${value}"
  [[ "/${value#/}/" != *'/../'* ]] || die "path traversal is not allowed: ${value}"
}

while (($# > 0)); do
  case "$1" in
    --domain)
      (($# >= 2)) || die '--domain requires a value'
      DOMAIN="$2"
      shift 2
      ;;
    --port)
      (($# >= 2)) || die '--port requires a value'
      CAMOUFLAGE_PORT="$2"
      shift 2
      ;;
    --client-host)
      (($# >= 2)) || die '--client-host requires a value'
      CLIENT_HOST="$2"
      shift 2
      ;;
    --cert-dir)
      (($# >= 2)) || die '--cert-dir requires a value'
      CERT_DIR="$2"
      shift 2
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

((EUID == 0)) || die 'run this installer as root'
[[ -n "$DOMAIN" ]] || die '--domain is required'
validate_domain "$DOMAIN"

CLIENT_HOST="${CLIENT_HOST:-$DOMAIN}"
validate_domain "$CLIENT_HOST"

if [[ ! "$CAMOUFLAGE_PORT" =~ ^[0-9]+$ ]] ||
  ((CAMOUFLAGE_PORT < 1024 || CAMOUFLAGE_PORT > 65535)); then
  die '--port must be an integer between 1024 and 65535'
fi

CERT_DIR="${CERT_DIR:-${CERT_ROOT}/${DOMAIN}}"
validate_absolute_path "$CERT_DIR"
readonly FULLCHAIN_FILE="${CERT_DIR}/fullchain.pem"
readonly PRIVATE_KEY_FILE="${CERT_DIR}/privkey.pem"

command -v docker >/dev/null 2>&1 ||
  die 'Docker is required. Install Remnawave Node/Docker first.'
docker compose version >/dev/null 2>&1 || die 'Docker Compose v2 is required.'
command -v curl >/dev/null 2>&1 || die 'curl is required.'
command -v openssl >/dev/null 2>&1 || die 'openssl is required.'

if ! docker info >/dev/null 2>&1; then
  die 'cannot access the Docker daemon; run as root or grant Docker access'
fi

validate_certificate() {
  [[ -s "$FULLCHAIN_FILE" ]] || die "missing certificate: ${FULLCHAIN_FILE}"
  [[ -s "$PRIVATE_KEY_FILE" ]] || die "missing private key: ${PRIVATE_KEY_FILE}"

  openssl x509 -in "$FULLCHAIN_FILE" -noout >/dev/null 2>&1 ||
    die "invalid certificate PEM: ${FULLCHAIN_FILE}"
  openssl pkey -in "$PRIVATE_KEY_FILE" -noout >/dev/null 2>&1 ||
    die "invalid private key PEM: ${PRIVATE_KEY_FILE}"
  openssl x509 -in "$FULLCHAIN_FILE" -noout -checkhost "$DOMAIN" >/dev/null 2>&1 ||
    die "certificate SAN does not cover ${DOMAIN}"
  openssl x509 -in "$FULLCHAIN_FILE" -noout -checkend 86400 >/dev/null 2>&1 ||
    die 'certificate expires in less than 24 hours'

  local certificate_key_hash private_key_hash
  certificate_key_hash="$({
    openssl x509 -in "$FULLCHAIN_FILE" -pubkey -noout |
      openssl pkey -pubin -outform DER 2>/dev/null
  } | openssl dgst -sha256)"
  private_key_hash="$(openssl pkey -in "$PRIVATE_KEY_FILE" -pubout -outform DER 2>/dev/null |
    openssl dgst -sha256)"
  [[ "$certificate_key_hash" == "$private_key_hash" ]] ||
    die 'certificate and private key do not match'
}

validate_dns_membership() {
  if ! command -v getent >/dev/null 2>&1; then
    warn 'getent is unavailable; DNS membership was not validated'
    return
  fi

  local public_ipv4 domain_points_here client_points_here
  local -a resolved_ipv4 client_ipv4
  mapfile -t resolved_ipv4 < <(
    getent ahostsv4 "$DOMAIN" | awk '{print $1}' | sort -u
  )
  ((${#resolved_ipv4[@]} > 0)) || die "${DOMAIN} has no resolvable IPv4 A record"
  log "${DOMAIN} currently resolves to: ${resolved_ipv4[*]}"

  public_ipv4="$(curl -4fsS --connect-timeout 5 --max-time 10 https://api.ipify.org || true)"
  if [[ -z "$public_ipv4" ]]; then
    warn 'could not determine this server public IPv4; DNS membership was not verified'
    return
  fi

  domain_points_here='false'
  for address in "${resolved_ipv4[@]}"; do
    if [[ "$address" == "$public_ipv4" ]]; then
      domain_points_here='true'
      break
    fi
  done
  [[ "$domain_points_here" == 'true' ]] ||
    die "${DOMAIN} DNS records do not include this server IPv4 (${public_ipv4})"

  if [[ "$CLIENT_HOST" != "$DOMAIN" ]]; then
    mapfile -t client_ipv4 < <(
      getent ahostsv4 "$CLIENT_HOST" | awk '{print $1}' | sort -u
    )
    ((${#client_ipv4[@]} > 0)) || die "${CLIENT_HOST} has no resolvable IPv4 A record"
    log "${CLIENT_HOST} currently resolves to: ${client_ipv4[*]}"

    client_points_here='false'
    for address in "${client_ipv4[@]}"; do
      if [[ "$address" == "$public_ipv4" ]]; then
        client_points_here='true'
        break
      fi
    done
    [[ "$client_points_here" == 'true' ]] ||
      die "${CLIENT_HOST} DNS records do not include this server IPv4 (${public_ipv4})"
  fi

  if getent ahostsv6 "$DOMAIN" >/dev/null 2>&1; then
    warn "${DOMAIN} has an AAAA record; include this node IPv6 or remove stale AAAA records"
  fi
}

port_owned_by_caddy() {
  docker ps --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"
}

port_is_listening() {
  local port="$1"
  command -v ss >/dev/null 2>&1 || return 1
  ss -H -ltn | awk '{print $4}' | grep -Eq "(^|:|\\])${port}$"
}

validate_certificate
validate_dns_membership

if port_is_listening "$CAMOUFLAGE_PORT" && ! port_owned_by_caddy; then
  die "local target port ${CAMOUFLAGE_PORT} is already occupied"
fi

umask 077
env_tmp="$(mktemp "${SCRIPT_DIR}/.env.caddy.XXXXXX")"
cleanup() {
  rm -f -- "$env_tmp"
}
trap cleanup EXIT

printf 'CAMOUFLAGE_DOMAIN=%s\n' "$DOMAIN" >"$env_tmp"
printf 'CAMOUFLAGE_PORT=%s\n' "$CAMOUFLAGE_PORT" >>"$env_tmp"
printf 'CAMOUFLAGE_CERT_DIR=%s\n' "$CERT_DIR" >>"$env_tmp"
mv -f -- "$env_tmp" "$ENV_FILE"
chmod 600 "$ENV_FILE"

compose() {
  docker compose \
    --env-file "$ENV_FILE" \
    --project-directory "$SCRIPT_DIR" \
    -f "$COMPOSE_FILE" "$@"
}

log 'Validating Docker Compose configuration'
compose config --quiet

log 'Building the React application and Caddy image'
compose build --pull

log 'Starting the camouflage site'
compose up -d --remove-orphans

log 'Waiting for the loopback HTTPS endpoint'
site_ready='false'
for _ in $(seq 1 30); do
  if curl --fail --silent --show-error \
    --connect-timeout 3 \
    --max-time 5 \
    --resolve "${DOMAIN}:${CAMOUFLAGE_PORT}:127.0.0.1" \
    "https://${DOMAIN}:${CAMOUFLAGE_PORT}/" \
    --output /dev/null; then
    site_ready='true'
    break
  fi
  sleep 2
done

if [[ "$site_ready" != 'true' ]]; then
  compose logs --tail=100 caddy-site >&2 || true
  die 'Caddy did not serve the installed certificate within 60 seconds'
fi

if command -v ss >/dev/null 2>&1; then
  if ss -H -ltn | awk '{print $4}' |
    grep -Eq "(^0\\.0\\.0\\.0:|^\[::\]:|^\\*:|^:::)${CAMOUFLAGE_PORT}$"; then
    die "port ${CAMOUFLAGE_PORT} is exposed publicly; expected loopback only"
  fi
fi

log 'Caddy camouflage site is ready'
compose ps

cat <<EOF

Remnawave values for this DNS-LB zone:

  Host Address: ${CLIENT_HOST}
  Host Port:    443
  SNI:          ${DOMAIN}

  "listen": "0.0.0.0",
  "port": 443,
  "streamSettings": {
    "network": "raw",
    "security": "reality",
    "realitySettings": {
      "target": "127.0.0.1:${CAMOUFLAGE_PORT}",
      "xver": 0,
      "serverNames": ["${DOMAIN}"],
      "privateKey": "USE_THE_SHARED_ZONE_REALITY_PRIVATE_KEY",
      "shortIds": ["USE_THE_SHARED_ZONE_SHORT_ID"]
    }
  }

For one DNS-balanced client connection, every node behind ${CLIENT_HOST}
must use the same REALITY public/private key pair, shortId, SNI, and port.

The local target port ${CAMOUFLAGE_PORT} must remain closed to the internet.
Public port 80 is not required. Xray owns public port 443.
