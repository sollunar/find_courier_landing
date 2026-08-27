# Find Courier landing

Public React landing page for Find Courier, plus a small Caddy deployment used
as the local HTTPS target for Remnawave/Xray REALITY. Certificate lifecycle and
infrastructure inventory deliberately live outside this repository.

## Frontend

```bash
npm ci --legacy-peer-deps
npm start
npm run build
```

The Caddy deployment does not change the visual design of the React app.

## Camouflage deployment

Xray owns public `443/tcp`. Caddy serves the landing page only on
`127.0.0.1:9443`, and Xray forwards ordinary TLS traffic to that local target.
Neither port `80` nor port `9443` needs to be public.

Prerequisites on a node:

- Linux with root access;
- Docker and Docker Compose v2;
- `bash`, `curl`, and `openssl`;
- a valid certificate already provisioned outside this repository as
  `fullchain.pem` and `privkey.pem` in a root-owned directory.

Deploy or update the site with:

```bash
./install-caddy.sh \
  --domain nl.find-courier.com \
  --client-host nl.whopn.org \
  --port 9443 \
  --cert-dir /opt/find-courier-camouflage/certs/nl.find-courier.com
```

Before starting Caddy, the installer checks that:

- the certificate and private key are valid PEM files and match each other;
- the certificate SAN covers `--domain` and is valid for at least 24 hours;
- the domain and optional client host resolve to this node;
- the target port is not occupied by another process.

It then mounts the certificate directory read-only into Caddy, verifies the
Compose configuration, builds the frontend image, starts the service, and
checks the loopback HTTPS endpoint. It never requests or renews certificates
and does not accept DNS-provider credentials.

Useful commands on a node:

```bash
docker compose --env-file .env.caddy -f docker-compose.caddy.yml ps
docker compose --env-file .env.caddy -f docker-compose.caddy.yml logs -f
docker compose --env-file .env.caddy -f docker-compose.caddy.yml up -d --build
```

## Remnawave/Xray values

For the example above, the relevant inbound fragment is:

```json
{
  "listen": "0.0.0.0",
  "port": 443,
  "protocol": "vless",
  "streamSettings": {
    "network": "raw",
    "security": "reality",
    "realitySettings": {
      "target": "127.0.0.1:9443",
      "xver": 0,
      "serverNames": ["nl.find-courier.com"],
      "privateKey": "SHARED_ZONE_REALITY_PRIVATE_KEY",
      "shortIds": ["SHARED_ZONE_SHORT_ID"]
    }
  }
}
```

A DNS-balanced client connection can use `nl.whopn.org:443` with SNI
`nl.find-courier.com`. Every node behind that connection must use the same
REALITY key pair, short ID, SNI, inbound port, and local target. DNS round-robin
does not remove unhealthy nodes; health monitoring and DNS changes are separate
operational responsibilities.
