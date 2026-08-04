# Ballerina Public API

The Ballerina Integration API is the public API boundary for SecureScan. It
validates client requests, persists the public scan lifecycle in PostgreSQL,
calls the internal Go scanner, and returns stable public response envelopes
without exposing internal service details.

This is currently a development/pre-auth API. The request's `authorized` field
is an explicit acknowledgement, not an authentication or authorization
control. Keep the listener private until the planned identity and
API-management layers are integrated.

Every public scan response includes an `X-Request-ID` header. Error response
bodies contain the same value in `error.requestId`, allowing an operator to
correlate a safe client error with the corresponding application logs.

## POST /api/v1/scans

Validates an authorized scan request and creates an asynchronous job in the Go
scanner.

### Request

```json
{
  "target": "scanme.nmap.org",
  "startPort": 1,
  "endPort": 100,
  "authorized": true
}
```

### Accepted response

Status: `202 Accepted`

```json
{
  "success": true,
  "data": {
    "id": "945686d6-c53f-4717-9d98-51f913fc8904",
    "status": "accepted",
    "target": "scanme.nmap.org",
    "startPort": 1,
    "endPort": 100
  }
}
```

The returned `id` is generated and owned by Ballerina. The internal Go scanner
ID is stored separately and is never exposed as the public identifier.

## GET /api/v1/scans/{scanId}

Validates the supplied UUID, loads the corresponding PostgreSQL job, refreshes
non-terminal state from the correlated Go scanner job, and returns the durable
public state and results.

Jobs follow this lifecycle:

```text
accepted -> running -> completed
                    -> failed
```

### Completed response

Status: `200 OK`

```json
{
  "success": true,
  "data": {
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
          "state": "closed"
        },
        {
          "address": "45.33.32.156",
          "port": 2,
          "state": "open"
        }
      ],
      "durationNanos": 1500000
    }
  }
}
```

Each result includes the resolved address that was scanned. This distinguishes
results when a hostname resolves to multiple IP addresses. Internal scanner and
per-port diagnostic strings are deliberately omitted from the public response.
An accepted, running, or failed job may not contain a `result`. Persisted detail
and result reads are owner-scoped, and result rows are always returned in
`address, port` order. Until WSO2 integration, that owner is the configured
development subject.

The persistence repository implements bounded scan-history reads ordered by
`created_at DESC, id DESC`, including a matching keyset cursor query. The public
`GET /api/v1/scans` collection resource is part of the Day 14 API checkpoint.

## Error response

The API maps validation and downstream failures to a stable public response:

```json
{
  "success": false,
  "error": {
    "code": "SCAN_NOT_FOUND",
    "message": "Scan not found",
    "requestId": "710ee544-7f9c-4ef0-a4c0-1d430ae649bf"
  }
}
```

Unexpected downstream payloads, internal URLs, and scanner diagnostic text are
never returned to public clients.

### Public error codes

| Code | HTTP status | Meaning |
| --- | ---: | --- |
| `INVALID_TARGET` | 400 | Target is missing or invalid |
| `INVALID_PORT_RANGE` | 400 | Port values are outside allowed boundaries |
| `INVALID_SCAN_ID` | 400 | Scan ID is not a valid UUID |
| `INVALID_REQUEST` | 400 | JSON body does not match the request contract |
| `BLOCKED_TARGET` | 400 | Target is not permitted |
| `SCAN_NOT_FOUND` | 404 | No job exists for the supplied UUID |
| `SCANNER_UNAVAILABLE` | 503 | Internal scanner is unreachable or timed out |
| `PERSISTENCE_UNAVAILABLE` | 503 | PostgreSQL cannot serve the scan operation |
| `INTERNAL_ERROR` | 500 | Unexpected internal or downstream response |
