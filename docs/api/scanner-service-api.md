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

The HTTP layer converts an incoming request into the same `ScanConfig` used
by the CLI. Therefore, both entry points enforce the Day 3 target, port,
timeout, allowlist and concurrency controls.

## Job Lifecycle

```text
accepted -> running -> completed
                    -> failed
```

The POST endpoint returns after storing a job. The scan runs in a background
goroutine, and clients poll the GET endpoint using the returned UUID.

Jobs are currently held in memory. Restarting the service removes all jobs.

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

```json
{
  "target": "scanme.nmap.org",
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
4. Validates and resolves the target.
5. Rejects blocked or non-allowlisted addresses.
6. Generates a random UUID v4.
7. Stores the job before starting asynchronous execution.

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
| `405 Method Not Allowed` | The endpoint does not support the HTTP method |
| `415 Unsupported Media Type` | A POST request is not JSON |
| `500 Internal Server Error` | The service could not create a scan ID |

Internal implementation details are not returned for unexpected server
errors. Request method and path are written to the service log.

## Security Boundary

The HTTP API is another untrusted-input boundary. It does not bypass scanner
validation. Private, loopback, link-local, multicast, unspecified and cloud
metadata addresses remain blocked according to the configured Day 3 policy.

The service must remain behind the Ballerina and API-management layers in
the final architecture. Those layers will add authentication, authorization,
rate limiting and public API controls.
