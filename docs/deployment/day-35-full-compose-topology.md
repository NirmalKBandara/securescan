# Day 35 — Full Docker Compose Topology

The local Compose project contains the complete six-service SecureScan shape:

```text
Browser -> frontend -> api-manager -> ballerina-api -> scanner-engine
               |             |               |
               +-> identity-server           +-> postgres
```

Only loopback browser and management listeners are published. PostgreSQL,
Ballerina, and Go have no host port and are reachable only through their
explicit service networks.

## Service and network boundaries

| Service | Networks | Published host ports | Starts after |
| --- | --- | --- | --- |
| `frontend` | `identity`, `gateway` | `127.0.0.1:3000` | healthy IS and APIM |
| `identity-server` | `identity` | `127.0.0.1:9443` | — |
| `api-manager` | `identity`, `gateway`, `integration` | `127.0.0.1:9444`, `127.0.0.1:8243` | healthy IS and Ballerina |
| `ballerina-api` | `integration`, `scanner`, `data` | none | healthy Go and PostgreSQL |
| `scanner-engine` | `scanner` | none | — |
| `postgres` | `data` | none | — |

`integration` and `data` are Docker-internal networks. The scanner network is
not marked internal because authorized scans require controlled outbound DNS
and TCP access; the scanner still has no inbound host port. There is no shared
default network, so unrelated tiers do not receive each other's DNS records.

The APIM project backend is now `http://ballerina-api:9090`. Re-import and
redeploy its revision after starting this topology; the previous
`host.docker.internal` endpoint belongs only to the host-run development path.

## Start from an empty application database

From the repository root:

```sh
cp deployment/.env.example deployment/.env
```

Replace the OIDC application placeholders and both 32-character secret
placeholders in the ignored `deployment/.env`. Then run:

```sh
docker compose \
  --env-file deployment/.env \
  --file deployment/compose.yaml \
  config --quiet
docker compose \
  --env-file deployment/.env \
  --file deployment/compose.yaml \
  up --detach --build --wait
docker compose \
  --env-file deployment/.env \
  --file deployment/compose.yaml \
  ps
```

On first initialization of the named PostgreSQL volume, the official entrypoint
runs only the six ordered `*.up.sql` migrations. Down migrations are never
mounted. PostgreSQL does not replay these files for a non-empty volume; use the
repository migration command when upgrading an existing development database.

WSO2 startup can take several minutes. Compose readiness ordering is:

```text
postgres + scanner-engine
          -> ballerina-api
identity-server + ballerina-api
          -> api-manager
identity-server + api-manager
          -> frontend
```

## Acceptance verification

After configuring `deployment/.env`, the executable check builds the three
application images, waits for all six health checks, verifies the three public
endpoints, rejects unexpected host ports, and tests positive and negative DNS
resolution across every service network:

```sh
deployment/verify-compose-topology.sh
```

Useful manual checks are:

```sh
docker compose --env-file deployment/.env -f deployment/compose.yaml ps
curl --fail http://127.0.0.1:3000/api/health
curl --fail --insecure https://127.0.0.1:9443/api/health-check/v1.0/health
curl --fail --insecure https://127.0.0.1:9444/publisher
docker network inspect securescan-data
docker network inspect securescan-scanner
```

## Known configuration boundary

The Compose topology uses internal WSO2 service names for server-to-server
traffic. A real login also requires the Next.js container to trust the WSO2
development certificate and the WSO2 issuer/redirect metadata to use names
reachable from both the browser and containers. Do not disable TLS verification.
The CA mount, hostnames, and environment validation belong to the Day 36
configuration/secret checkpoint; the full login-to-results recovery run is the
Day 37 acceptance gate.

## Local verification record

YAML parsing, the six-service inventory, health-check coverage, internal-network
presence, loopback-only publication set, shell syntax, and whitespace checks
pass locally. Docker is not installed on the implementation workstation, so
image pulls, live readiness, and the executable network matrix remain pending
on a Docker-capable host.
