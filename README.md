# SecureScan

SecureScan is a defense-in-depth platform for authorized TCP connect scanning.
Authenticated users can submit an allowlisted target and bounded port range,
follow the asynchronous job, and review durable results. Administrators manage
target policy, inspect audit events, and review usage across users.

> Use SecureScan only against systems you own or have explicit permission to
> test. See the [authorized-use policy](docs/security/authorized-use-policy.md).

## Project status

The Day 41 clean-room source checkpoint is complete. The application, API contracts,
database migrations, local six-service topology, security controls, automated
tests, and maintained documentation are present in the repository.

“Repository-complete” is not a claim that the stateful deployment gate has run
on this workstation. A release still requires the authorized WSO2, browser,
PostgreSQL, real-scan, restart, and dependency-recovery exercise in the
[Day 37 runbook](docs/deployment/day-37-compose-recovery.md). Docker is not
available in the current restricted workspace, so that live evidence remains
pending.

The administrator UI and protected API resources are implemented, but the
ordinary frontend OAuth client requests only `securescan:scan`. A separate
privileged client or safe incremental grant for `securescan:admin` must be
implemented and verified before claiming the browser-admin Gateway path is
deployable.

## Architecture

```text
Browser
  │  OIDC Authorization Code + PKCE
  ▼
Next.js ───────────────► WSO2 Identity Server
  │ access token unsealed from an encrypted HttpOnly session cookie
  ▼
WSO2 API Manager
  │ token validation, scopes, throttling, trusted identity mediation
  ▼
Ballerina API ─────────► PostgreSQL
  │ validation, authorization, lifecycle, audit
  ▼
Go scanner engine
  │ pinned, safety-checked TCP connections
  ▼
Authorized target
```

The browser stores the encrypted HttpOnly session cookie but client-side
JavaScript cannot read its tokens. Next.js alone unseals it and sends the access
token upstream. API Manager is the public API policy boundary; Ballerina
independently enforces identity, ownership, roles,
target policy, request limits, and audit behavior. Go revalidates the complete
DNS address set and dials only the authorized addresses supplied by Ballerina.
PostgreSQL is the system of record for jobs, results, target policy, and audit
events.

See the [maintained architecture](docs/architecture/architecture-v1.md) for
trust boundaries, networks, lifecycle, and failure behavior.
The [diagram set](docs/architecture/flows.md) separately visualizes the system,
login/API request flow, and Compose networks.

## Components

| Component | Responsibility | Guide |
| --- | --- | --- |
| Next.js | OIDC session, protected UI, same-origin Gateway proxy | [Frontend](frontend/README.md) |
| WSO2 Identity Server | Authentication, OIDC tokens, application roles | [Identity setup](docs/identity/day-22-wso2-oidc-client.md) |
| WSO2 API Manager | API publication, token validation, scopes, CORS, throttling | [Gateway publishing](docs/gateway/day-27-api-manager-publishing.md) |
| Ballerina | Public contract, authorization, orchestration, persistence, audit | [Ballerina API](ballerina-api/README.md) |
| Go | Internal asynchronous scanner and final DNS/target safety checks | [Scanner engine](scanner-engine/README.md) |
| PostgreSQL | Durable lifecycle, observations, allowlist, audit ledger | [Database](database/README.md) |

The [documentation index](docs/README.md) provides reading paths for users,
operators, contributors, reviewers, and API consumers.

## Quick verification

The complete source gate requires Go 1.26.4, Java 21 with Ballerina 2201.13.4,
Node.js 20.9 or newer, npm, Bash, and ripgrep. Install frontend dependencies
once, then run:

```sh
cd frontend
npm ci
cd ..
./scripts/verify.sh
```

Run a single boundary while developing:

```sh
./scripts/verify.sh go
./scripts/verify.sh ballerina
./scripts/verify.sh frontend
./scripts/verify.sh repository
```

To prove that ignored files and an existing dependency tree are not masking a
problem, run the same source gate from a temporary archive of committed `HEAD`:

```sh
./scripts/verify-clean-room.sh all
```

The [Day 41 evidence record](docs/project/day-41-clean-room-evidence.md) records
the observed clean-room result and keeps the pending WSO2/Docker screenshots
and demonstration separate from source verification.

The repository gate checks shell syntax, local Markdown links, secret patterns,
and whitespace. PostgreSQL verification runs in CI against a disposable
PostgreSQL 16 service; the equivalent local commands are documented in the
[database guide](database/README.md).

## Local platform setup

The full platform requires Docker Engine with Compose, sufficient resources for
both WSO2 products, locally trusted certificates whose SANs match the Compose
service names, and explicit WSO2 application/API configuration. It is not an
unauthenticated one-command scanner.

1. Follow the [configuration and secret runbook](docs/deployment/day-36-configuration-secrets.md)
   to generate the non-WSO2 values and bootstrap only PostgreSQL, Go,
   Ballerina, Identity Server, and API Manager.
2. Register the confidential OIDC client and roles using the
   [identity guide](docs/identity/day-22-wso2-oidc-client.md), then put its real
   values into the ignored environment file.
3. Import, publish, subscribe, and configure the API using the
   [API Manager guide](docs/gateway/day-27-api-manager-publishing.md) and
   [Gateway routing guide](docs/gateway/day-28-gateway-routing.md).
4. Provision WSO2 certificates using the product configuration, then install
   the issuing [frontend CA bundle](deployment/certs/README.md). Certificate
   issuance and WSO2 keystore wiring are manual prerequisites, not automated by
   this repository.
5. Validate the completed environment, start all six services, and verify their
   isolation using the [deployment guide](deployment/README.md).
6. Create authorized target rules before attempting a scan; follow the
   [target-administration guide](docs/security/day-30-allowed-target-administration.md).
7. Before treating the environment as deployable, complete the
   [security checkpoint](docs/security/day-33-security-checkpoint.md) and
   [recovery gate](docs/deployment/day-37-compose-recovery.md).

Published development listeners bind to loopback by default:

| Service | URL |
| --- | --- |
| Frontend | `http://localhost:3000` |
| Identity Server console | `https://localhost:9443/console` |
| API Manager Publisher | `https://localhost:9444/publisher` |
| API Manager Developer Portal | `https://localhost:9444/devportal` |
| API Gateway | `https://localhost:8243` |

PostgreSQL, Ballerina, and Go have no published host ports in the Compose
topology.

## Security properties

- Exact `securescan-user` and `securescan-admin` roles; lookalikes fail closed.
- Owner-scoped scan detail/history and independent administrator authorization.
- Exact hostname/IP/CIDR target rules with complete port-range containment.
- Admission-time and pre-dispatch DNS safety checks with final address pinning.
- Private, loopback, link-local, multicast, metadata, unspecified, and reviewed
  special-use address ranges blocked outside isolated tests.
- A maximum of 1,000 ports per request plus body, timeout, concurrency, active
  job, retention, and Gateway subscription limits.
- Transactional lifecycle and audit events with safe, constrained metadata.
- Non-root application images, segmented networks, loopback-only public ports,
  secret preflight checks, and no silent direct-backend fallback.

The [threat model](docs/security/threat-model.md) is the authoritative control
and residual-risk summary.

## Scan lifecycle

1. The user authenticates through WSO2 and submits an acknowledged scan.
2. API Manager validates the access token, scope, subscription, and quota.
3. Ballerina validates identity, input, target policy, DNS answers, port range,
   and active-job limits, then commits a durable `QUEUED` job.
4. A leased background dispatch sends the public job ID and authorized address
   pins to Go idempotently.
5. Go re-resolves the target, requires the DNS set to match, and scans only the
   pins within bounded concurrency and timeouts.
6. Ballerina reconciles status and atomically commits terminal results and audit
   events. Polling and history always read the durable owner-scoped record.

Public and internal schemas are documented separately in the
[Ballerina public API](docs/api/ballerina-public-api.md) and
[scanner service API](docs/api/scanner-service-api.md).

## Roadmap

- [x] Scanner safety, asynchronous jobs, and internal API
- [x] Ballerina orchestration, persistence, history, and audit logging
- [x] Next.js scan workflow and administrator dashboard
- [x] WSO2 Identity Server authentication and role enforcement
- [x] WSO2 API Manager publication, routing, scopes, and throttling artifacts
- [x] PostgreSQL migrations and local development tooling
- [x] Hardened application images and six-service Compose topology
- [x] Configuration, secret, integration, and recovery procedures
- [x] Cross-stack automated tests and continuous integration
- [x] Complete maintained project documentation
- [x] Reconcile OpenAPI and architecture/login/deployment diagrams
- [x] Pass all source gates from a clean tracked-files-only checkout
- [ ] Capture redacted WSO2, Gateway, container, persistence, admin, and video evidence
- [ ] Complete the privileged browser-admin OAuth scope flow
- [ ] Capture the live Day 37 deployment evidence on a Docker-capable host

## License

SecureScan is available under the [MIT License](LICENSE).
