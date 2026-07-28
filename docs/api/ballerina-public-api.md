# Ballerina Public API

The Ballerina Integration API is the public API boundary for SecureScan.
It validates client requests before any request can reach the internal Go scanner service.

## POST /api/v1/scans

Creates a scan request after public API validation.
For now, only validates the request contract. 
It does not call the Go scanner yet.

### Request

```json
{
  "target": "scanme.nmap.org",
  "startPort": 1,
  "endPort": 100,
  "authorized": true
}
```

### Accepted Response

Status: 202 Accepted

```json
{
  "success": true,
  "data": {
    "UUID": "contract-validation-only",
    "status": "validated",
    "target": "scanme.nmap.org",
    "startPort": 1,
    "endPort": 100
  }
}
```

### Validation Errors

Status: 400 Bad Request

```json
{
  "success": false,
  "error": {
    "code": "INVALID_PORT_RANGE",
    "message": "Start port must be less than or equal to end port",
    "details": {
      "startPort": 100,
      "endPort": 1
    }
  }
}
```

### Public Error Codes

| Code | Meaning |
|---|---|
| `INVALID_TARGET` | Target is missing or invalid |
| `INVALID_PORT_RANGE` | Port values are outside allowed boundaries |
| `BLOCKED_TARGET` | Request is not allowed by the public safety policy |
| `SCANNER_UNAVAILABLE` | Internal scanner cannot be reached |
| `INTERNAL_ERROR` | Unexpected server error |
