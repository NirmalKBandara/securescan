# Day 40 — OpenAPI and complete documentation

Day 40 reconciles the machine-readable contract and the maintained project
guides with the final repository state.

## Completion record

- The OpenAPI document covers every Ballerina resource, including the private
  unauthenticated `/health` liveness operation.
- OAuth authorization-code URLs, user/admin scopes, role bindings, operation
  parameters, response status codes, schemas, examples, and the stable error
  envelope are documented.
- The public API guide lists all implemented error codes and explains the
  private health endpoint.
- Architecture, OIDC/Gateway login, and Compose deployment diagrams live in
  [one maintained diagram set](../architecture/flows.md).
- The root README and documentation index link setup, architecture,
  authentication/API management, database, restrictions, tests, recovery, and
  troubleshooting to their authoritative guides.

## OpenAPI coverage inventory

| Resource | OpenAPI operation | Authentication |
| --- | --- | --- |
| `GET /health` | `getHealth` | None; private liveness |
| `POST /api/v1/scans` | `createScan` | `securescan:scan` |
| `GET /api/v1/scans` | `listScans` | `securescan:scan` |
| `GET /api/v1/scans/{scanId}` | `getScan` | `securescan:scan` |
| `GET /api/v1/admin/scans` | `listAdminScans` | `securescan:admin` |
| `GET /api/v1/admin/audit-logs` | `listAuditLogs` | `securescan:admin` |
| `GET /api/v1/admin/usage` | `getAdminUsage` | `securescan:admin` |
| `GET /api/v1/admin/allowed-targets` | `listAllowedTargets` | `securescan:admin` |
| `POST /api/v1/admin/allowed-targets` | `createAllowedTarget` | `securescan:admin` |
| `DELETE /api/v1/admin/allowed-targets/{targetId}` | `disableAllowedTarget` | `securescan:admin` |

## WSO2 contribution candidate

The genuine beginner-sized candidate identified on 21 August 2026 is
[wso2/docs-apim issue #11557](https://github.com/wso2/docs-apim/issues/11557),
“Image links are broken in the API keys doc.” It is open, labeled
`good-first-issue`, unassigned, and scoped to documentation for API Manager
4.7.0. Its project field says “In Progress,” so a contributor should first
comment to confirm that work is not already underway and then reproduce every
broken image against the current documentation branch before editing. This is
a candidate, not a claim that an external contribution was submitted.

## Verification boundary

The offline documentation, secret-pattern, shell-syntax, and whitespace gates
can run in this workspace. WSO2/browser behavior and the clean six-service
deployment still require the Day 41 evidence exercise on a Docker-capable host.

