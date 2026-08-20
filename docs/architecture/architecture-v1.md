# SecureScan architecture — version 1

SecureScan is a six-service, defense-in-depth system for authenticated and
authorized TCP connect scans. This document describes the repository-complete
Day 39 architecture. The [threat model](../security/threat-model.md) owns the
detailed threat/control analysis, and the
[authorized-use policy](../security/authorized-use-policy.md) governs use.

## System context

```text
Browser
  │  HTTPS / OIDC Authorization Code + PKCE
  ├──────────────────────────────► WSO2 Identity Server
  ▼
Next.js frontend
  │  HTTPS / access token unsealed from encrypted HttpOnly cookie
  ▼
WSO2 API Manager
  │  private HTTP / trusted identity mediation
  ▼
Ballerina integration API ─────────────► PostgreSQL
  │  private HTTP / authorized address pins
  ▼
Go scanner engine
  │  bounded TCP connect attempts
  ▼
Authorized target
```

Only the frontend, Identity Server, API Manager portals, and HTTPS Gateway bind
to host loopback. Ballerina and PostgreSQL are on Docker `internal` networks;
Go is unpublished and reachable only on the application network.

## Component responsibilities

| Component | Owns | Does not own |
| --- | --- | --- |
| Next.js | Browser UI, OIDC PKCE flow, encrypted HttpOnly session, protected routes, same-origin API proxy | Scan authorization or durable data |
| WSO2 Identity Server | Authentication, OIDC tokens, user identity and application-role claims | API subscription or target policy |
| WSO2 API Manager | Public API lifecycle, access-token validation, scopes, subscriptions, CORS, throttling, trusted identity mediation | Job lifecycle or scanner safety |
| Ballerina | Public API, trusted caller identity, exact roles, ownership, validation, target policy, orchestration, persistence, audit | Raw network connections |
| Go scanner | Internal jobs, DNS-set verification, address safety, pinned dialing, scan concurrency and timeouts | Public identity or allowlist administration |
| PostgreSQL | Jobs, result observations, allowed-target rules, audit events, dispatch leases, migration ledger | Authentication credentials or transient frontend sessions |

## Trust boundaries

### Browser to frontend

The browser is untrusted. Next.js validates OIDC state, nonce, PKCE, token
signatures and claims before creating a bounded encrypted HttpOnly session
cookie. The browser stores that ciphertext, but client-side JavaScript cannot
read the tokens and only Next.js can unseal them. Protected pages require an exact
`securescan-user` or `securescan-admin` role, and `/admin` repeats the exact
administrator check inside the server-rendered page.

### Frontend to API Manager

The authenticated `/backend` route discards browser-supplied identity headers
and does not forward application cookies. In the default `gateway` mode it adds
the session's access token and calls the configured API Manager context. Missing
Gateway configuration fails closed. The direct Ballerina mode is an explicit
development fallback, not an automatic production bypass.

### API Manager to Ballerina

API Manager validates the token, subscription, operation scope, quota, and CORS
policy. Its inbound mediation adds the authenticated subject and roles plus a
shared backend secret. Ballerina requires that secret when authentication is
enabled, trusts identity only on this protected hop, and independently enforces
ownership and exact administrator roles. The Ballerina listener remains
unpublished in Compose.

### Ballerina to scanner

Ballerina authorizes the target against enabled exact-hostname, exact-IP, or
CIDR rules and safety-checks every resolved address. Dispatch includes the
complete authorized address set. Go resolves the hostname again, requires an
exact DNS-set match, rechecks every address and limit, and dials only the pins.
This closes the time-of-check/time-of-use DNS gap without trusting Ballerina to
perform network I/O.

### Application services to PostgreSQL

Only Ballerina reads or writes application records. Lifecycle changes and their
audit event commit in the same transaction. Terminal result observations and
the terminal job state also commit atomically. Database constraints enforce
status shape, uniqueness, referential integrity, target-rule form, and safe
audit metadata.

## Network segmentation

| Network | Members | Purpose |
| --- | --- | --- |
| `identity` | Identity Server, API Manager, frontend | OIDC and token-service traffic |
| `gateway` | API Manager, frontend | Published API path |
| `integration` | API Manager, Ballerina | Private Gateway-to-service hop; internal |
| `scanner` | Ballerina, Go | Private scan-dispatch hop |
| `data` | Ballerina, PostgreSQL | Private persistence hop; internal |

No single application container joins every network. Network separation reduces
accidental discovery; application authentication, authorization, and safety
checks remain mandatory even on private networks.

## Authenticated request flow

1. Next.js starts Authorization Code with PKCE at Identity Server.
2. The callback validates the authorization response and seals identity and
   tokens into the encrypted HttpOnly session cookie.
3. The browser calls same-origin `/backend`; Next.js attaches the access token
   on the server.
4. API Manager validates the token and applies `securescan:scan` or
   `securescan:admin`, subscription, CORS, and throttling policy.
5. Trusted mediation forwards normalized subject/role headers and the shared
   backend secret to Ballerina.
6. Ballerina authenticates the hop and authorizes the resource, owner, or exact
   administrator role before reading or changing state.

Frontend route checks improve user experience but never replace the API-layer
checks.

## Scan lifecycle

```text
QUEUED ──dispatch──► RUNNING ──result transaction──► COMPLETED
   │                     │
   ├──policy change────► BLOCKED
   └──dispatch error────► FAILED ◄──scanner failure──┘
```

1. Ballerina validates JSON size and shape, the explicit authorized-use
   acknowledgement, port bounds, active-job limits, target policy, and all DNS
   answers.
2. It creates the public UUID and commits a `QUEUED` job plus requested audit
   event before contacting Go. This makes `202 Accepted` durable.
3. A dispatch lease prevents concurrent reconcilers from owning the same queued
   row. The public UUID is also the idempotency key on the internal request.
4. Go validates request correlation, target, ports, authorized pins, DNS set,
   address safety, capacity, and timeouts before starting bounded TCP connects.
5. Polling and periodic reconciliation recover work after transient Ballerina or
   scanner outages. Strict response correlation rejects mismatched downstream
   data.
6. Ballerina commits terminal observations, job status, and audit attribution
   transactionally. Owner-scoped detail and keyset history read only durable
   state in deterministic order.

## Data ownership

- `scan_jobs.id` is the stable public scan identifier.
- `scanner_scan_id` is private downstream correlation.
- `scan_results` contains safe address/port/state observations, not raw scanner
  diagnostic text.
- `allowed_targets` contains versioned soft-disable policy and complete
  port-range bounds.
- `audit_logs` is append-only lifecycle and administration attribution
  with an action-specific metadata allowlist.
- Frontend sessions and OAuth tokens are not stored in the application database.

The [schema design](../database/schema-design.md) defines tables, indexes,
constraints, transactions, and migrations.

## Capacity and failure behavior

- API Manager applies separate user and administrator subscription policies.
- Next.js and Ballerina cap request bodies; Ballerina and Go cap ports at 1,000.
- Ballerina limits one active scan per owner; Go additionally bounds global
  active jobs, worker concurrency, retained jobs, and TCP duration.
- Missing identity, roles, policy, configuration, or trusted-hop credentials
  fails closed.
- Dependency errors map to stable public envelopes with request IDs; internal
  diagnostics remain in structured service logs.
- Health-aware Compose dependencies order cold start. PostgreSQL migrations run
  on an empty volume and the migration ledger records the initialized state.
- The recovery harness uses isolated volumes and networks to verify cold start,
  two real flows, restart persistence, and four dependency outages.

## Deployment boundary

The repository contains pinned application builds, the six-service Compose
topology, environment validation, secret checks, API Manager artifacts, tests,
and recovery automation. WSO2 applications, roles, API import, subscriptions,
certificates, and authorized targets are stateful operator configuration; they
are not fabricated by source tests.

Before deployment, run the [automated test gate](../testing/day-38-automated-tests.md),
complete the [security checkpoint](../security/day-33-security-checkpoint.md),
and capture the [Compose recovery evidence](../deployment/day-37-compose-recovery.md)
on a Docker-capable host. The last gate remains pending in the current
restricted workspace.
