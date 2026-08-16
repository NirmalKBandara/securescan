# SecureScan Architecture — Version 1

The maintained security boundaries, threats, automated evidence, and residual
deployment checks are defined in the
[`SecureScan threat model`](../security/threat-model.md). Authorized operation
is governed by the
[`authorized-use policy`](../security/authorized-use-policy.md).

## Overview

SecureScan is composed of multiple services, with each component responsible for a specific part of the system.

## Components

### Next.js Frontend

Provides the user interface for authentication, submitting scan requests, viewing scan status, and reviewing results.

### WSO2 Identity Server

Handles user authentication, OAuth 2.0, OpenID Connect, and role-based access.

### WSO2 API Manager

Protects and manages the SecureScan API through token validation, throttling, policies, and API lifecycle management.

### Ballerina Integration API

Validates requests, applies business rules, coordinates scan jobs, communicates with the Go scanner, and accesses PostgreSQL.

### Go Scanner Engine

Performs controlled TCP connection scans against authorized targets.

### PostgreSQL

Stores scan jobs, scan results, allowed targets, audit logs, and related metadata.

## Request Flow

```text
1. The user opens the Next.js frontend.
2. The user logs in through WSO2 Identity Server.
3. Identity Server provides authentication tokens.
4. The frontend sends a scan request through WSO2 API Manager.
5. API Manager validates the request and applies throttling.
6. Ballerina validates the target and creates the scan job.
7. Ballerina sends the job to the Go scanner engine.
8. The scanner performs the controlled scan.
9. Results are stored in PostgreSQL.
10. The frontend retrieves and displays the results.
```

## Implemented persistence checkpoint (Day 13)

The repository currently implements the first service boundary in this
architecture:

```text
Public client
  -> Ballerina POST /api/v1/scans
  -> Go POST /internal/scans
  -> PostgreSQL scan job with a separate internal Go job correlation
  -> Ballerina GET /api/v1/scans/{scanId}
  -> Go GET /internal/scans/{scanId}
```

Ballerina owns the public contract and durable public scan ID, validates the acknowledgement and basic
port boundaries, applies downstream connection/response timeouts, generates a
request ID, and removes scanner diagnostics from public responses. The Go
service remains responsible for DNS revalidation, allowlist enforcement,
private/special-range blocking, scan limits, and TCP connections.

The Ballerina-owned `scan_jobs.id` is the public identifier. The Go identifier
is stored separately as `scanner_scan_id`; status polling uses that private
correlation and persists lifecycle changes and terminal port observations.
Completion takes a row lock and commits the complete observation batch with the
terminal job update in one PostgreSQL transaction. Duplicate completion attempts
become no-ops after the first commit. Owner-scoped detail/result queries and
keyset scan-history queries use stable database ordering; exposing the history
query as a public collection resource remains Day 14 work.

Next.js is now in the development request path, and a local WSO2 Identity
Server runtime is available from the Day 21 Compose foundation. Day 22 defines
the confidential OIDC client, exact callbacks, scopes, and application-role
contract. Day 23 wires WSO2 into the browser path with Authorization Code plus
PKCE and an encrypted server-managed frontend session. Day 24 gates product
routes on exact SecureScan application roles and repeats privileged checks in
the admin server boundary. PostgreSQL is the durable scan system of record.
Until identity and API management integration is complete, the Ballerina
listener is a private development endpoint and `authorized: true` is only an
explicit-use acknowledgement, not an authentication mechanism.

## Initial Diagram

```text
                  ┌─────────────────────────┐
                  │  WSO2 Identity Server   │
                  │ Login, OAuth2, OIDC     │
                  └────────────▲────────────┘
                               │
┌──────────┐       ┌───────────┴───────────┐
│   User   │──────▶│   Next.js Frontend    │
└──────────┘       └───────────┬───────────┘
                               │
                               ▼
                  ┌─────────────────────────┐
                  │    WSO2 API Manager     │
                  │ Security + Throttling   │
                  └────────────┬────────────┘
                               │
                               ▼
                  ┌─────────────────────────┐
                  │ Ballerina Integration   │
                  │ Validation + Workflow   │
                  └───────┬─────────┬───────┘
                          │         │
                          │         ▼
                          │   ┌──────────────┐
                          │   │ PostgreSQL   │
                          │   │ Jobs + Logs  │
                          │   └──────────────┘
                          │
                          ▼
                  ┌─────────────────────────┐
                  │    Go Scanner Engine    │
                  │ Controlled TCP Scans    │
                  └────────────┬────────────┘
                               │
                               ▼
                     Authorized Target
```

## Status

The Ballerina-to-Go integration, PostgreSQL persistence, scan frontend, and
local WSO2 Identity Server runtime checkpoints are implemented. Authentication
flows, authorization enforcement, and API management remain future integration
phases.
