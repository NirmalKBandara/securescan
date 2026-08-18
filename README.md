# SecureScan

SecureScan is a secure API-managed network scanning platform built as a personal project to demonstrate modern API management, identity, integration, networking, and deployment practices.

## Project Overview

SecureScan allows authenticated users to submit authorized network scan requests and view their scan results through a web interface.

## Problem Statement

Network scanning tools can be difficult to manage securely. SecureScan aims to provide a controlled system with authentication, authorization, rate limiting, target validation, audit logging, and scan history.

## Main Features

- Secure user authentication
- Role-based access control
- Authorized target scanning
- API throttling
- Scan history
- Administrator dashboard
- Audit logging
- Docker-based local deployment

## Technology Stack

- Next.js
- TypeScript
- WSO2 Identity Server
- WSO2 API Manager
- Ballerina
- Go
- PostgreSQL
- Docker Compose

## Architecture

```text
User
  ↓
Next.js Frontend
  ↓
WSO2 Identity Server
  ↓
WSO2 API Manager
  ↓
Ballerina Integration API
  ↓
Go Scanner Engine
  ↓
PostgreSQL
```

## Current Status

The Go scanner engine and Ballerina integration API now provide a complete
asynchronous scan flow. Public clients can create authorized scan jobs and
retrieve their status and safe results through Ballerina. The integration
includes target and port validation, downstream timeouts, safe error mapping,
request correlation IDs, structured logging, and automated tests.

The current Ballerina listener is a development/pre-auth API. Its `authorized`
field records the caller's acknowledgement; WSO2 Identity Server and API
Manager will provide authentication and policy enforcement in later phases.

The Day 14 asynchronous lifecycle is complete. Ballerina commits a durable
queued job before dispatch, submits it idempotently to Go, and periodically
reconciles status and results. Owner and global active-job limits bound work;
durable dispatch leases, strict response correlation, and transactional result
completion make outage and retry behavior deterministic. Detail and history
queries remain owner-scoped and deterministically ordered.

The Day 15 data-layer checkpoint is complete. Requested, started, completed,
blocked, and failed scan transitions append a constrained audit event in the
same PostgreSQL transaction as the job/result change. Each event carries the
owner, actor, request ID, public scan ID, database timestamp, and only
action-specific safe metadata. Database constraints reject duplicate lifecycle
events and metadata containing fields outside the allowlist.

The Day 20 frontend checkpoint is complete. The `frontend` workspace uses
Next.js 16, React 19, strict TypeScript, and responsive plain CSS. Users can
submit validated scan requests, follow active jobs to terminal results, and
filter durable scan history through the typed Ballerina client boundary.

The Day 21 identity foundation is complete. The local Compose project now runs
the pinned WSO2 Identity Server 7.3.0 image with loopback-only TLS exposure, a
readiness check, and durable development identity data. OIDC application
registration, frontend sessions, role enforcement, and API token validation
remain separate integration checkpoints.

The Day 22 OIDC client foundation is complete. SecureScan now has an explicit
confidential-client configuration contract for the WSO2 issuer, exact callback
and logout URLs, Authorization Code with PKCE, server-only credentials, and the
future `securescan-user` / `securescan-admin` role boundary. Browser sessions
and route enforcement follow in the Day 23 and Day 24 checkpoints.

The Day 23 login checkpoint is complete. Next.js now performs Authorization
Code with PKCE against WSO2, validates the authorization response and ID token,
stores identity only in bounded encrypted HttpOnly sessions, safely restores
internal destinations, and coordinates local plus provider logout. Protected
routes and administrator authorization are added by Day 24.

The Day 24 authorization checkpoint is complete. Next.js now protects the
dashboard, scan, history, and administration routes from invalid sessions,
admits only identities with an exact SecureScan application role, and enforces
`securescan-admin` again inside the admin page. Navigation and the accessible
forbidden path reflect the same centralized policy.

The Day 25 ownership checkpoint is complete. New scans and lifecycle audit
events carry the authenticated subject, ordinary users can retrieve only their
own detail and history records, and the API independently authorizes exact
administrator roles for cross-user reads. The Next.js backend route forwards
identity from the encrypted session without exposing tokens to browser code.

The Day 26 API Manager foundation pins WSO2 API Manager 4.7.0 in the local
Compose topology and records the Publisher, Developer Portal, Gateway,
application, subscription, lifecycle, throttling, backend, and token-validation
plan. Live portal verification remains pending on a Docker-capable host.

The Day 27 repository artifacts are ready for API Manager import: a complete
OpenAPI v1 contract, versioned API Controller project, Ballerina backend
endpoint, identity-header mediation, and executable Gateway acceptance check.
Live import, subscription, and invocation evidence remains pending on a host
with Docker and API Controller.

The Day 28 frontend cutover is repository-complete. The authenticated Next.js
proxy now targets API Manager by default, requests the API scope, keeps access
tokens server-side, rejects silent Ballerina bypass, and normalizes Gateway
failures for the UI. The API project adds scope/role bindings and exact-origin
CORS. Live browser acceptance remains pending with the Day 27 runtime evidence.

The Day 29 security-limit checkpoint is repository-complete. Separate user and
administrator subscription policies protect Gateway capacity; the application
independently enforces one active scan per owner, a 1,000-port maximum, a
4,096-byte request maximum, bounded timeouts, safe throttling responses, and
direct-backend authentication. Live WSO2 quota and recovery evidence remains
pending on a Docker-capable host.

The Day 30 allowed-target checkpoint is repository-complete. PostgreSQL stores
distinct exact hostname, exact IP, and CIDR policy rules; administrator-only
APIs list, create, and soft-disable them; and every change commits with
immutable actor, request, target, and timestamp attribution. Live WSO2
role/scope acceptance remains pending on a Docker-capable host.

The Day 31 target-authorization checkpoint is repository-complete. Every scan
must match an enabled hostname, IP, or CIDR policy for its complete port range;
hostnames are resolved and every address is safety-checked both at admission
and immediately before dispatch. Unsafe, unauthorized, expired, or disabled
targets are blocked before reaching the scanner and recorded with immutable
audit attribution. Live DNS-transition evidence remains pending on a
Docker-capable host with PostgreSQL and WSO2.

The Day 32 administrator-dashboard checkpoint is repository-complete. Exact
administrators can review scans across users, filter by owner and lifecycle,
inspect safe audit events and usage counts, and create or disable target rules
from the responsive Next.js interface. The page, Gateway scope, and Ballerina
API each enforce the administrator boundary. Live WSO2 role/scope evidence
remains pending on a Docker-capable host.

The Day 33 repository security checkpoint is complete. Authentication bypasses
are restricted to fixed isolated tests, browser identity-header spoofing is
discarded, role lookalikes cannot gain administrator access, and Ballerina's
authorized DNS address set is pinned through Go to the final dial. Unsafe and
special-use addresses, DNS set changes, more than 16 answers, and more than
1,000 ports fail closed. The live multi-user/WSO2/PostgreSQL matrix remains a
required pre-deployment gate.

The Day 34 application-container checkpoint is repository-complete. Go,
Ballerina, and Next.js use lean multi-stage builds, non-root runtime users,
service health checks, and build contexts that exclude local dependencies and
configuration files. Live image builds remain pending on a Docker-capable host.

The Day 35 Compose topology is repository-complete. All six services have
health-aware dependency ordering, PostgreSQL bootstraps an empty volume with
ordered migrations, application-only networks limit service discovery, and
only loopback frontend/WSO2 ports are published. Live Compose acceptance
remains pending on a Docker-capable host.

The Day 36 configuration checkpoint is repository-complete. Compose now fails
clearly for missing credentials, a preflight validates the complete local
environment without sourcing it, frontend and Ballerina reject placeholder
secrets during startup, and generated WSO2 state is excluded from Git. A
tracked-file and Git-history credential check plus a single WSO2/database setup
runbook make the local boundary reproducible. Live Compose validation remains
pending on a Docker-capable host.

## Security Notice

SecureScan is intended only for systems that the user owns or has explicit permission to test. 
Unauthorized scanning is prohibited.

## Roadmap

* [x] Initialize repository
* [x] Create project structure
* [x] Refactor Go scanner engine
* [x] Add scanner target validation
* [x] Add scan safety controls
* [x] Add internal Go scanner HTTP service
* [x] Add asynchronous scan jobs and status retrieval
* [x] Build Ballerina API
* [x] Design PostgreSQL schema and migration plan
* [x] Add PostgreSQL schema and local migrations
* [x] Persist Ballerina scan jobs and results in PostgreSQL
* [x] Make result completion transactional and add scan history queries
* [x] Complete durable asynchronous endpoints and recovery
* [x] Add transactional scan lifecycle audit logging
* [x] Initialize the Next.js frontend and required routes
* [x] Build reusable scan UI and connect it to the API
* [x] Add WSO2 Identity Server local development foundation
* [x] Integrate WSO2 Identity Server
* [ ] Integrate WSO2 API Manager
* [x] Add PostgreSQL Docker Compose service
* [x] Add application Dockerfiles and health checks
* [x] Compose the complete six-service topology
* [x] Harden deployment configuration and secret handling
* [ ] Add automated tests
* [ ] Complete documentation

A more detailed architecture draft is available in [`architecture`](docs/architecture/architecture-v1.md).

The scanner's internal API is documented in
[`scanner-service-api`](docs/api/scanner-service-api.md).

The reviewed PostgreSQL design and migration plan are documented in
[`schema-design`](docs/database/schema-design.md).

Local database commands are documented in
[`database development`](database/README.md).

The frontend foundation and its acceptance evidence are documented in
[`Day 16 frontend foundation`](docs/frontend/day-16-foundation.md).

The local identity runtime and its security boundary are documented in
[`Day 21 identity server foundation`](docs/identity/day-21-wso2-identity-server.md).

The OIDC application registration and configuration contract are documented in
[`Day 22 OIDC client foundation`](docs/identity/day-22-wso2-oidc-client.md).

The frontend login, callback, session, and logout guarantees are documented in
[`Day 23 OIDC login`](docs/identity/day-23-oidc-login.md).

The protected-route matrix and role enforcement are documented in
[`Day 24 route authorization`](docs/identity/day-24-route-authorization.md).

Authenticated scan ownership and API-side RBAC are documented in
[`Day 25 ownership and RBAC`](docs/identity/day-25-ownership-rbac.md).

The API management runtime and publishing plan are documented in
[`Day 26 API Manager foundation`](docs/gateway/day-26-wso2-api-manager.md).

The import, publication, subscription, and Gateway verification runbook is in
[`Day 27 API Manager publishing`](docs/gateway/day-27-api-manager-publishing.md).

The frontend Gateway cutover, Developer Portal application setup, scope and
identity checks, and browser acceptance run are documented in
[`Day 28 Gateway routing`](docs/gateway/day-28-gateway-routing.md).

The throttling tiers, layered application limits, API versioning policy, and
live quota/bypass acceptance procedure are documented in
[`Day 29 API throttling`](docs/gateway/day-29-api-throttling.md).

The allowed-target data model, administrator API, transactional audit rules,
and acceptance procedure are documented in
[`Day 30 allowed-target administration`](docs/security/day-30-allowed-target-administration.md).

The enforced allowlist decision, all-address DNS safety checks, rebinding
defenses, and blocked-attempt evidence are documented in
[`Day 31 target authorization`](docs/security/day-31-target-authorization.md).

The all-user scan review, audit visibility, usage counts, target-policy controls,
and layered role enforcement are documented in
[`Day 32 administrator dashboard`](docs/frontend/day-32-administrator-dashboard.md).

The authorization, DNS pinning, abuse-limit, and audit evidence is documented
in [`Day 33 security checkpoint`](docs/security/day-33-security-checkpoint.md),
with the maintained [`threat model`](docs/security/threat-model.md) and
[`authorized-use policy`](docs/security/authorized-use-policy.md).

The image build, non-root runtime, and independent health-check procedure is
documented in
[`Day 34 application Dockerfiles`](docs/deployment/day-34-application-dockerfiles.md).

The complete service graph, database bootstrap, port boundary, dependency
ordering, and DNS-isolation checks are documented in
[`Day 35 full Compose topology`](docs/deployment/day-35-full-compose-topology.md).

The validated environment contract, WSO2 initialization order, migration
procedure, and secret-review evidence are documented in
[`Day 36 configuration and secrets`](docs/deployment/day-36-configuration-secrets.md).
