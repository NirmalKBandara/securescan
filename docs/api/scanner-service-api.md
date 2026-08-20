# Scanner Service API

## Overview

The Go scanner engine is an internal HTTP service. It is designed for calls
from trusted SecureScan components such as the Ballerina integration layer,
not for direct public internet exposure.

The service listens on port `8081` by default and communicates using JSON.

## Architecture

```text
Ballerina integration service
        |
        | HTTP + JSON
        v
Go scanner HTTP service
        |
        | validates target and limits
        v
In-memory job store
        |
        | asynchronous execution
        v
TCP connect scanner
```

The HTTP layer converts an incoming request into `ScanConfig`, including the
exact address set authorized by Ballerina. Production HTTP requests must carry
those pins; Go verifies the current DNS set and later dials only the pins.

## Job Lifecycle

```text
accepted -> running -> completed
                    -> failed
```

The POST endpoint returns after storing a job. The scan runs in a background
goroutine, and clients poll the GET endpoint using the returned UUID.

Jobs are held in memory. Active work is bounded by `MAX_ACTIVE_SCANS` (default
10), and the oldest terminal jobs are evicted after `MAX_RETAINED_JOBS`
(default 1000). Restarting the service removes all jobs.

## GET /health

Reports whether the HTTP process is running.

Successful response: `200 OK`

```json
{
  "status": "ok",
  "service": "securescan-scanner"
}
```

## POST /internal/scans

Validates and creates a scan job.

The request must use `Content-Type: application/json`.

Retry-capable callers should also send `X-Idempotency-Key` containing the
durable public scan UUID. The same key with the same normalized target and port
range returns the original job and never starts a second goroutine. Reusing a
key for different scan parameters returns `409 IDEMPOTENCY_CONFLICT`. The
idempotency header remains optional, but the authorized address set is required
outside loopback-isolated development.

```json
{
  "target": "scanme.nmap.org",
  "authorizedAddresses": ["45.33.32.156"],
  "startPort": 1,
  "endPort": 100
}
```

Accepted response: `202 Accepted`

```json
{
  "id": "945686d6-c53f-4717-9d98-51f913fc8904",
  "status": "accepted",
  "target": "scanme.nmap.org",
  "startPort": 1,
  "endPort": 100
}
```

Before accepting the job, the service:

1. Limits the request body to 4096 bytes.
2. Rejects malformed JSON, unknown fields and trailing JSON values.
3. Validates the requested port range and configured limits.
4. Requires at most 16 Ballerina-authorized addresses in production.
5. Validates every pin, requires the current DNS set to match exactly, and
   rejects blocked, special-use, or non-allowlisted addresses.
6. Applies idempotency and the global active-job limit atomically.
7. Generates a random UUID v4 for newly admitted work.
8. Stores the job and pins before starting asynchronous execution; the scanner
   dials those pins without resolving the hostname again.

## GET /internal/scans/{id}

Returns the current state of a scan job.

Successful response: `200 OK`

```json
{
  "id": "945686d6-c53f-4717-9d98-51f913fc8904",
  "status": "completed",
  "target": "scanme.nmap.org",
  "startPort": 1,
  "endPort": 2,
  "createdAt": "2026-07-25T10:00:00Z",
  "updatedAt": "2026-07-25T10:00:01Z",
  "result": {
    "target": "scanme.nmap.org",
    "startPort": 1,
    "endPort": 2,
    "results": [
      {
        "address": "45.33.32.156",
        "port": 1,
        "state": "closed",
        "error": "connection refused"
      }
    ],
    "duration": 1500000
  }
}
```

`address` identifies the validated resolved IP that was scanned. A hostname can
resolve to multiple addresses, so the same port may appear once for each
address. `duration` is a Go duration represented in nanoseconds.

Failed jobs use the `failed` status and contain an `error` field instead of
a result.

## Error Handling

Errors always use a JSON object:

```json
{
  "code": "SCAN_NOT_FOUND",
  "error": "scan job not found"
}
```

The machine-readable `code` is the integration contract used by Ballerina.
Human-readable error text remains diagnostic and must not be used for public
error classification.

The service uses these HTTP status codes:

| Status | Meaning |
| --- | --- |
| `200 OK` | Health or scan-job retrieval succeeded |
| `202 Accepted` | A validated scan job was created |
| `400 Bad Request` | JSON, target, port range or scan ID is invalid |
| `404 Not Found` | The requested scan job does not exist |
| `409 Conflict` | An idempotency key was reused for different scan parameters |
| `429 Too Many Requests` | The global active-job limit has been reached |
| `405 Method Not Allowed` | The endpoint does not support the HTTP method |
| `415 Unsupported Media Type` | A POST request is not JSON |
| `500 Internal Server Error` | The service could not create a scan ID |

Internal implementation details are not returned for unexpected server
errors. Request method and path are written to the service log.

## Security Boundary

The HTTP API is another untrusted-input boundary. It does not bypass scanner
validation. Private, loopback, link-local, multicast, unspecified, cloud
metadata, and reviewed special-use ranges remain blocked. IPv4-mapped IPv6
addresses are unmapped before classification.

Unpinned requests and `ALLOW_PRIVATE_TARGETS=true` require
`SCANNER_ISOLATED_DEVELOPMENT=true`, which forces the listener to
`127.0.0.1:8081`. That mode is for isolated testing and is not a production
compatibility path.

The service remains behind Ballerina and API Manager in the implemented Compose
architecture. API Manager applies public authentication, scopes, subscriptions,
and throttling; Ballerina applies trusted-hop authentication, ownership, roles,
target policy, lifecycle, and audit controls. These upstream layers do not
replace the scanner's own address, DNS-set, port, concurrency, and timeout
checks.
