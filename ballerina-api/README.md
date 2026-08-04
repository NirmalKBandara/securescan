# SecureScan Ballerina Integration API

The Ballerina Integration API is the public application-service layer for
SecureScan. It validates public requests, orchestrates scanner jobs, and
communicates with the Go scanner engine, and persists scan lifecycle and results
in PostgreSQL.

The service is currently a development/pre-auth API. The `authorized` request
field is an explicit user acknowledgement, not an authentication or
authorization control. Keep the listener private until WSO2 identity and API
management are integrated.

## Current Status

- A configurable HTTP listener
- `GET /health`
- Stable success and error response envelopes
- An automated health endpoint test
- Public scan creation contract: `POST /api/v1/scans`
- Request validation for required target, port boundaries, and authorized-use confirmation
- `GET /api/v1/scans/{scanId}`
- Configurable scanner connection and response timeouts
- Safe public mapping for validation, blocked, not-found, unavailable, and internal errors
- Generated `X-Request-ID` response headers and structured application logs
- Ballerina-owned durable public scan IDs with separate Go scanner correlation
- PostgreSQL-backed lifecycle and result retrieval
- Transactional, retry-safe result synchronization before a job becomes terminal
- Owner-scoped detail/result reads and bounded keyset history queries

## Requirements

- Ballerina Swan Lake 2201.13.4
- Java 21

## Configuration

Copy `Config.example.toml` to the ignored `Config.toml` and adjust it for the
local environment:

```toml
listenerPort = 9090
serviceName = "securescan-api"

# Internal Go scanner address; never expose this in public responses.
scannerServiceUrl = "http://localhost:8081"

# Downstream timeouts in seconds.
scannerConnectTimeout = 2.0
scannerResponseTimeout = 5.0

persistenceEnabled = true
databaseHost = "localhost"
databasePort = 5432
databaseName = "securescan_dev"
databaseUser = "securescan"
databasePassword = "securescan_dev_only"
developmentOwnerSubject = "development-user"
```

Primitive configuration values can also be overridden using environment
variables:

```bash
BAL_CONFIG_VAR_LISTENERPORT=9092 \
BAL_CONFIG_VAR_SERVICENAME=securescan-api-local \
bal run
```

`developmentOwnerSubject` is temporary until WSO2 supplies an authenticated
subject. Do not commit passwords, tokens, or other credentials to `Config.toml`.

## Run

Start and migrate PostgreSQL first using the commands in `database/README.md`.
Then, from the `ballerina-api` directory: `bal run`
The service starts on: http://localhost:9090

## Health Check

```bash
curl --include http://localhost:9090/health
```

## Format

```bash
bal format
```

## Test

```bash
bal test
```

Tests use port `9091`, configured through `tests/Config.toml`.

## Build

```bash
bal build
```

Generated build artifacts are written to `target/`.

## Create a Scan

```bash
curl --include \
  --request POST \
  --header "Content-Type: application/json" \
  --data '{"target":"scanme.nmap.org","startPort":1,"endPort":100,"authorized":true}' \
  http://localhost:9090/api/v1/scans
```

## Get Scan Status

Copy the `id` returned by the create request and use it here:

```bash
curl --include \
  http://localhost:9090/api/v1/scans/945686d6-c53f-4717-9d98-51f913fc8904
```

This ID is owned by Ballerina and remains stable independently of the internal
Go scanner ID.

## Persistence Guarantees

Lifecycle writes are conditional on the current database status and report
whether a row was changed. Completion locks the active job, batch-inserts every
address/port observation, and marks the job `COMPLETED` in one transaction. A
database error rolls the complete operation back; a duplicate completion sees
the terminal row and performs no writes.

Detail and result reads include the owner subject. Results are ordered by
`address, port`. The repository also provides bounded first-page and keyset
history queries ordered by `created_at DESC, id DESC`; the public collection
resource that exposes this query is scheduled for Day 14.

Scan jobs progress through:

```text
accepted -> running -> completed
                    -> failed
```

Every public scan response includes an `X-Request-ID` header. Error responses
also include the same value in `error.requestId`.
