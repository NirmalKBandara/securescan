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

The Day 10 PostgreSQL design is also complete: the four required tables,
constraints, indexes, ownership rules, status lifecycle, service-ID
correlation, required queries, and versioned migration sequence are specified.
Executable migrations and database wiring intentionally begin on Day 11.

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
* [ ] Add PostgreSQL storage
* [ ] Build Next.js frontend
* [ ] Integrate WSO2 Identity Server
* [ ] Integrate WSO2 API Manager
* [ ] Add Docker Compose
* [ ] Add automated tests
* [ ] Complete documentation

A more detailed architecture draft is available in [`architecture`](docs/architecture/architecture-v1.md).

The scanner's internal API is documented in
[`scanner-service-api`](docs/api/scanner-service-api.md).

The reviewed PostgreSQL design and migration plan are documented in
[`schema-design`](docs/database/schema-design.md).
