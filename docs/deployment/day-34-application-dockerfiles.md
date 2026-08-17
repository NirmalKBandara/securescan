# Day 34 — Application Dockerfiles

SecureScan now builds the Go scanner, Ballerina integration API, and Next.js
frontend as three self-contained images. No image needs a source-code mount or
host-installed application dependencies at runtime.

## Image design

| Image | Build stage | Runtime | Runtime user | Health endpoint |
| --- | --- | --- | --- | --- |
| `securescan-scanner` | Go 1.26 Alpine | Alpine with CA certificates | `securescan` | `GET :8081/health` |
| `securescan-api` | Ballerina 2201.13.4 | Java 21 JRE Alpine | `securescan` | `GET :9090/health` |
| `securescan-frontend` | Node 24 Alpine | Next.js standalone on Node 24 Alpine | `nextjs` | `GET :3000/api/health` |

The build contexts exclude local dependencies, generated output, logs, Git
metadata, and environment files. In particular, `ballerina-api/Config.toml`
and frontend `.env*` files are never copied into an image. Configuration and
secrets are supplied only when a container starts.

## Clean builds

Run from the repository root:

```sh
docker build --no-cache --tag securescan-scanner:day34 scanner-engine
docker build --no-cache --tag securescan-api:day34 ballerina-api
docker build --no-cache --tag securescan-frontend:day34 frontend
```

The frontend's browser API path defaults to `/backend`. Override it at build
time only when a different public path is intentional:

```sh
docker build \
  --build-arg NEXT_PUBLIC_API_BASE_URL=/backend \
  --tag securescan-frontend:day34 frontend
```

## Independent smoke checks

The scanner has no service dependency:

```sh
docker run --detach --name securescan-scanner-day34 \
  --publish 127.0.0.1:8081:8081 \
  securescan-scanner:day34
curl --fail http://127.0.0.1:8081/health
```

The Ballerina API intentionally fails closed without its PostgreSQL system of
record. Its independent image check therefore needs reachable PostgreSQL and
scanner containers, but does not mount source files. The Day 35 Compose stack
provides those dependencies and the required schema initialization.

The frontend can be checked without either backend because its health resource
does not perform authentication or dependency probes:

```sh
docker run --detach --name securescan-frontend-day34 \
  --publish 127.0.0.1:3000:3000 \
  --env NEXT_PUBLIC_API_BASE_URL=/backend \
  --env APP_BASE_URL=http://localhost:3000 \
  --env OIDC_ISSUER=https://localhost:9443/oauth2/token \
  --env OIDC_CLIENT_ID=day34-smoke-check \
  --env OIDC_CLIENT_SECRET=day34-smoke-check \
  --env AUTH_SESSION_SECRET=replace-with-at-least-32-characters \
  --env SECURESCAN_API_MODE=gateway \
  --env API_MANAGER_GATEWAY_URL=https://localhost:8243/securescan/v1 \
  securescan-frontend:day34
curl --fail http://127.0.0.1:3000/api/health
```

Check the built-in health status and configured non-root users:

```sh
docker inspect --format '{{.State.Health.Status}} {{.Config.User}}' \
  securescan-scanner-day34
docker inspect --format '{{.State.Health.Status}} {{.Config.User}}' \
  securescan-frontend-day34
```

Remove only these named smoke-check containers when finished:

```sh
docker rm --force securescan-scanner-day34 securescan-frontend-day34
```

## Local verification record

The native Go test/build, Ballerina 47-test suite and executable build, and
frontend lint, type check, 83 tests, and production build pass. Docker is not
installed on the implementation workstation, so the three clean image builds
and live container health checks must be run on a Docker-capable host before
recording the acceptance check as executed.
