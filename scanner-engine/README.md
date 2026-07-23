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
- Added structured scan models
- Added error handling
- Removed reliance on shell commands

## Package Structure

```text
scanner-engine/
├── cmd/server/main.go
├── internal/models/models.go
├── internal/scanner/scanner.go
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
  -end-port 25 \
  -timeout 1s
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

* Scanning is sequential
* Open and closed are the only displayed states
* Private and unsafe network ranges are not yet blocked
* Hostname resolution safety controls are not yet implemented
* Concurrency controls are not yet implemented
