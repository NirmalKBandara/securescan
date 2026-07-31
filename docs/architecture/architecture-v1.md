# SecureScan Architecture — Version 1

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

## Implemented integration checkpoint (Day 09)

The repository currently implements the first service boundary in this
architecture:

```text
Public client
  -> Ballerina POST /api/v1/scans
  -> Go POST /internal/scans
  -> asynchronous in-memory Go job
  -> Ballerina GET /api/v1/scans/{scanId}
  -> Go GET /internal/scans/{scanId}
```

Ballerina owns the public contract, validates the acknowledgement and basic
port boundaries, applies downstream connection/response timeouts, generates a
request ID, and removes scanner diagnostics from public responses. The Go
service remains responsible for DNS revalidation, allowlist enforcement,
private/special-range blocking, scan limits, and TCP connections.

The current Go job identifier is returned directly as the public identifier.
Day 10 introduces a durable Ballerina-owned `scan_jobs.id` and records the Go
identifier separately as `scanner_scan_id`; the database design documents that
correlation and its lifecycle constraints.

PostgreSQL, WSO2, and Next.js are architectural targets and are not yet in the
runtime request path. Until WSO2 is integrated, the Ballerina listener is a
private development endpoint and `authorized: true` is only an explicit-use
acknowledgement, not an authentication mechanism.

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

The Ballerina-to-Go integration checkpoint is implemented and tested. The
PostgreSQL schema is designed but persistence is intentionally scheduled for
the next implementation phase.
