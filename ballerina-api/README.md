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
- Durable `QUEUED` responses before the Go scanner is contacted
- Background scanner submission with periodic and polling-driven recovery
- Idempotent Go submission using the durable public scan ID
- Strict scanner ID, target, port-range, and result correlation checks
- Owner-level active-job admission limits
- `GET /api/v1/scans` history with bounded keyset pagination

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
maxActiveScansPerOwner = 5
dispatchLeaseSeconds = 15
reconciliationIntervalSeconds = 5
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

Creation returns `202 Accepted` with `status: "queued"` immediately after the
job commits to PostgreSQL. Go submission continues asynchronously. A periodic
reconciler and detail polling synchronize running/completed results and retry a
queued job that could not be submitted while the scanner was unavailable. A
durable, expiring database lease prevents background reconciliation and
concurrent polls from dispatching the same queued row simultaneously. The
public scan UUID is sent to Go as `X-Idempotency-Key`, so retrying an ambiguous
submission returns the original scanner job instead of starting another scan.
Validation or policy failures from Go become durable `FAILED`/`BLOCKED` jobs;
transient scanner unavailability or capacity pressure leaves the job queued for
recovery. A running scanner job that permanently disappears becomes `FAILED`.

At most `maxActiveScansPerOwner` `QUEUED`/`RUNNING` jobs may exist for one
owner. Admission is serialized in PostgreSQL, and excess requests return `429`
with `JOB_LIMIT_REACHED` without creating a row.

`dispatchLeaseSeconds` must remain longer than `scannerResponseTimeout`, and
`reconciliationIntervalSeconds` must be positive. Invalid asynchronous
configuration stops the API during startup rather than accepting jobs it cannot
dispatch. If an API process stops while holding a lease, periodic reconciliation
or a later poll recovers the queued row after expiry. Scanner responses must
match the stored scanner ID, target, and port range before any lifecycle or
result data is committed.

## Scan History

```bash
curl --include \
  'http://localhost:9090/api/v1/scans?pageSize=20'
```

History is ordered by `created_at DESC, id DESC`. For the next keyset page,
send both values from the final item:

```text
?pageSize=20&cursorCreatedAt=<createdAt>&cursorId=<id>
```

`pageSize` must be between 1 and 100. Until WSO2 integration, all rows are
scoped to `developmentOwnerSubject`.

## Persistence Guarantees

Lifecycle writes are conditional on the current database status and report
whether a row was changed. Completion locks the active job, batch-inserts every
address/port observation, and marks the job `COMPLETED` in one transaction. A
database error rolls the complete operation back; a duplicate completion sees
the terminal row and performs no writes.

Detail and result reads include the owner subject. Results are ordered by
`address, port`. The repository and public collection resource provide bounded
first-page and keyset history queries ordered by `created_at DESC, id DESC`.

Scan jobs progress through:

```text
queued -> running -> completed
       -> blocked
       -> failed
```

Every public scan response includes an `X-Request-ID` header. Error responses
also include the same value in `error.requestId`.
