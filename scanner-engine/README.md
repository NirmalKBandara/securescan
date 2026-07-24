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

## Package Structure

```text
scanner-engine/
├── cmd/server/main.go
├── internal/config/config.go
├── internal/models/models.go
├── internal/scanner/scanner.go
├── internal/validation/ports.go
├── internal/validation/validation.go
└── go.mod
````

### `cmd/server`

Contains the command-line entry point. It reads command-line flags,
creates a scan configuration, starts the scanner and displays results.

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
MAX_PORTS_PER_SCAN=1000
MAX_CONCURRENT_PORTS=100
SCAN_TIMEOUT_MS=1000
ALLOWED_TARGETS=
```

`ALLOWED_TARGETS` is an optional comma-separated allowlist. When it is set,
only exact matching hostnames or IP addresses are accepted.

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

## Run

```bash
go run ./cmd/server \
  -target scanme.nmap.org \
  -start-port 20 \
  -end-port 25
```

## Build

```bash
go build ./...
```

## Test

```bash
go test ./...
```

## Current Limitations

* Open and closed are the only displayed states
