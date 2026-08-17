# SecureScan Scanner Engine

The scanner engine is the Go component responsible for controlled TCP
connect scanning within SecureScan.

> Use this software only against systems you own or are explicitly
> authorized to test.

## Current Status

- Refactored scanner into separate Go packages
- Added TCP connect scanning with Go's `net` package
- Added configurable per-port connection timeouts
- Added port-range validation
- Limited scans to a maximum of 1000 ports
- Added IPv4, IPv6 and hostname validation
- Added DNS resolution before scanning
- Blocked unsafe target address types by default
- Added configurable scan concurrency limits
- Added development target allowlist support
- Added structured scan models
- Added error handling
- Removed reliance on shell commands
- Added an internal HTTP service on port 8081
- Added health, scan creation and scan status endpoints
- Added UUID-based asynchronous scan jobs
- Added idempotent job creation and global active-job admission limits
- Bounded retained terminal jobs to prevent unbounded in-memory growth
- Added structured JSON responses and request logging

## Package Structure

```text
scanner-engine/
├── cmd/
│   ├── cli/main.go
│   └── server/
│       ├── main.go
│       ├── scans.go
│       ├── jobs.go
│       ├── get_scan.go
│       └── uuid.go
├── internal/config/config.go
├── internal/models/models.go
├── internal/scanner/scanner.go
├── internal/validation/ports.go
├── internal/validation/validation.go
└── go.mod
```

### `cmd/server`

Contains the internal HTTP service. It accepts JSON scan requests, validates
them, stores jobs in memory and runs scans asynchronously.

### `cmd/cli`

Contains the original command-line scanner. It remains available for direct
development and debugging.

### `internal/models`

Contains shared request and response structures used by the scanner.

### `internal/scanner`

Contains the TCP connect scanning implementation.

### `internal/validation`

Validates targets, TCP port ranges, maximum port limits and timeout
configuration.

## Target Safety

SecureScan validates each target before scanning.

Validation flow:

1. Accept a host string, not a full URL.
2. Parse direct IPv4 and IPv6 addresses.
3. Validate hostname syntax for non-IP targets.
4. Resolve hostnames to IP addresses.
5. Reject the target if any resolved IP is unsafe.
6. Scan only the validated IP addresses.
7. Enforce port count, timeout and concurrency limits.

Blocked by default:

* Private ranges such as `10.0.0.0/8`, `172.16.0.0/12` and `192.168.0.0/16`
* Loopback addresses such as `127.0.0.0/8` and `::1`
* Link-local addresses such as `169.254.0.0/16` and `fe80::/10`
* Multicast addresses such as `224.0.0.0/4` and `ff00::/8`
* Unspecified addresses such as `0.0.0.0` and `::`
* Cloud metadata addresses such as `169.254.169.254` and `fd00:ec2::254`

These controls reduce SSRF and accidental misuse risk by preventing users
from using the scanner as a path into localhost-only services, private
networks, link-local services or cloud metadata endpoints.

More detail is available in
[`docs/security/target-validation.md`](../docs/security/target-validation.md).

## Configuration

```text
ALLOW_PRIVATE_TARGETS=false
SCANNER_ISOLATED_DEVELOPMENT=false
MAX_PORTS_PER_SCAN=1000
MAX_CONCURRENT_PORTS=100
MAX_ACTIVE_SCANS=10
MAX_RETAINED_JOBS=1000
SCAN_TIMEOUT_MS=1000
ALLOWED_TARGETS=
```

`ALLOWED_TARGETS` is an optional comma-separated allowlist. When it is set,
only exact matching hostnames or IP addresses are accepted.

The HTTP service requires Ballerina to send the exact authorized DNS address
set with each scan. Unpinned requests are accepted only when
`SCANNER_ISOLATED_DEVELOPMENT=true`; that mode retains the scanner's local
resolve-validate-dial flow and binds the HTTP service to `127.0.0.1`.
`ALLOW_PRIVATE_TARGETS` is rejected at startup unless the same
isolated-development flag is enabled.

`MAX_ACTIVE_SCANS` is the process-wide maximum number of accepted/running scan
jobs. Additional new jobs receive `429 JOB_LIMIT_REACHED`; retries of an
existing idempotent request remain available. `MAX_RETAINED_JOBS` bounds the
number of completed/failed jobs retained for status lookup. The oldest terminal
jobs and their idempotency mappings are evicted after that limit is exceeded.

## How TCP Connect Scanning Works

TCP connect scanning attempts to establish a complete TCP connection with
each requested port.

If the connection succeeds, the port is classified as open. If the
connection is rejected, times out or otherwise fails, the port is currently
classified as closed.

The scanner uses:

```go
net.DialTimeout("tcp", address, timeout)
```

Each successful connection is closed immediately after detection.

## Why Native Go Networking Is Used

SecureScan uses Go's standard `net` package rather than executing external
commands such as `nmap`, `nc` or shell scripts.

This approach:

* Avoids shell-command injection
* Avoids dependence on external executables
* Provides direct timeout control
* Provides structured Go errors
* Improves portability
* Makes the scanner easier to test and maintain

## Run HTTP Service

```bash
go run ./cmd/server
```

The service listens on `http://localhost:8081`. Its endpoints are:

```text
GET  /health
POST /internal/scans
GET  /internal/scans/{id}
```

Callers that may retry creation should send the durable public scan UUID as
`X-Idempotency-Key`. Repeating the same key and target/port request returns the
same scanner job without starting another scan. Reusing a key for different
scan parameters returns `409 IDEMPOTENCY_CONFLICT`. Omitting the header preserves
the original behavior and creates a new scanner job.

Full request, response and error documentation is available in
[`scanner-service-api.md`](../docs/api/scanner-service-api.md).

## Run CLI

```bash
go run ./cmd/cli \
  -target scanme.nmap.org \
  -start-port 20 \
  -end-port 25
```

## Build

```bash
go build ./...
```

Build the non-root runtime image from the repository root:

```bash
docker build --tag securescan-scanner:local scanner-engine
```

## Test

```bash
go test ./...
```

## Current Limitations

* Open and closed are the only displayed states
* Scan jobs are kept in memory, bounded by active and terminal-job limits, and
  are lost when the service restarts
* Authentication and authorization will be handled by later platform layers
