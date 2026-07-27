# SecureScan Ballerina Integration API

The Ballerina Integration API is the public application-service layer for SecureScan. 
It will validate public requests, orchestrate scanner jobs, communicate with the Go scanner engine, and access PostgreSQL.

## Current Status

- A configurable HTTP listener
- `GET /health`
- Stable success and error response envelopes
- An automated health endpoint test
- Public scan creation contract: `POST /api/v1/scans`
- Request validation for required target, port boundaries, and authorized-use confirmation

---> The Ballerina service does not communicate with the Go scanner yet.

## Requirements

- Ballerina Swan Lake 2201.13.4
- Java 21

## Configuration

Local development configuration is stored in `Config.toml`:

```toml
listenerPort = 9090
serviceName = "securescan-api"
```

Primitive configuration values can also be overridden using environment
variables:

```bash
BAL_CONFIG_VAR_LISTENERPORT=9092 \
BAL_CONFIG_VAR_SERVICENAME=securescan-api-local \
bal run
```

*Do not commit passwords, tokens, or other credentials to `Config.toml`.*

## Run

From the `ballerina-api` directory: `bal run`
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

## Create Scan Contract Check

```bash
curl --include \
  --request POST \
  --header "Content-Type: application/json" \
  --data '{"target":"scanme.nmap.org","startPort":1,"endPort":100,"authorized":true}' \
  http://localhost:9090/api/v1/scans
  ```
  