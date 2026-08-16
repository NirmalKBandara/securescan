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

Validates an authorized scan request, commits a durable `QUEUED` job, and then
submits it to the Go scanner in the background.

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
    "status": "queued",
    "target": "scanme.nmap.org",
    "startPort": 1,
    "endPort": 100
  }
}
```

The returned `id` is generated and owned by Ballerina. The internal Go scanner
ID is stored separately and is never exposed as the public identifier.

The response is sent after PostgreSQL commits and does not wait for the Go
scanner. At most `maxActiveScansPerOwner` queued/running jobs are admitted for
one owner; excess requests return `429 JOB_LIMIT_REACHED` without creating a
row. A durable dispatch lease prevents a background submission from racing an
immediate status poll. Ballerina sends the public scan UUID to Go as an
idempotency key, making an ambiguous submission safe to retry. Expired leases
are retried by periodic reconciliation or later polls after an outage or
service restart.

## GET /api/v1/scans/{scanId}

Validates the supplied UUID, loads the corresponding PostgreSQL job, refreshes
non-terminal state from the correlated Go scanner job, and returns the durable
public state and results.

Jobs follow this lifecycle:

```text
queued -> running -> completed
       -> blocked
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

## GET /api/v1/scans

Returns the authenticated owner's durable jobs ordered by
`created_at DESC, id DESC`. `pageSize` defaults to 20 and must be from 1 to 100.
For the next keyset page, supply both `cursorCreatedAt` and `cursorId` from the
last item in the current page.

```text
GET /api/v1/scans?pageSize=20
GET /api/v1/scans?pageSize=20&cursorCreatedAt=2026-08-05T10:00:00Z&cursorId=945686d6-c53f-4717-9d98-51f913fc8904
```

Until WSO2 integration, ownership is scoped with the configured development
subject.

## Administrator resources

All `/api/v1/admin/*` resources require the exact `securescan-admin` role in
addition to Gateway authentication and the `securescan:admin` scope. Ordinary
users receive `403`.

`GET /api/v1/admin/scans` returns jobs across owners with optional
`ownerSubject` and `status` filters. `pageSize` defaults to 50 and is bounded to
100. Items add `ownerSubject` and the safe terminal `failureCode` to the normal
history projection.

`GET /api/v1/admin/audit-logs` returns up to 100 newest immutable events with
their timestamp, actor, owner, action, outcome, correlation/resource IDs, and
database-constrained safe metadata.

`GET /api/v1/admin/usage` returns distinct-owner and lifecycle counts plus the
number of enabled allowed-target policies.

`GET` and `POST /api/v1/admin/allowed-targets` list and create exact hostname,
IP, or CIDR rules. `DELETE /api/v1/admin/allowed-targets/{targetId}` soft-disables
the rule and retains its audit history; it does not hard-delete the row.

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
| `JOB_LIMIT_REACHED` | 429 | The owner already has the configured maximum active jobs |
| `INTERNAL_ERROR` | 500 | Unexpected internal or downstream response |

## Dispatch recovery guarantee

Transient scanner unavailability or Go capacity pressure leaves a job queued.
Periodic reconciliation and detail polling retry submission after the durable
lease expires. The retry uses the public UUID as `X-Idempotency-Key`, so a Go
job accepted before an ambiguous timeout is returned rather than duplicated.
Permanent validation/policy failures become terminal `FAILED`/`BLOCKED`
records, and a correlated scanner job that later disappears becomes `FAILED`.
Scanner IDs, targets, port ranges, and completed result ranges must match the
durable public job before synchronization is accepted.

## Audit guarantee

Durable scan creation and every applied lifecycle transition append an audit
record atomically with the corresponding job/result write. The event sequence
for a successful scan is `SCAN_REQUESTED`, `SCAN_STARTED`, and
`SCAN_COMPLETED`; a policy-blocked scan records `SCAN_REQUESTED` and
`SCAN_BLOCKED`; other terminal failures record `SCAN_FAILED` after the last
applied state.

Audit rows correlate the owner/user subject, service actor, `X-Request-ID`, and
public scan UUID without exposing them through this public API. Metadata has a
database-enforced per-action allowlist and never stores targets, resolved
addresses, raw diagnostics, request bodies, headers, credentials, or tokens.
Conditional state updates plus a unique lifecycle-event index make retries
idempotent. An audit-write failure rolls back the paired lifecycle mutation.
