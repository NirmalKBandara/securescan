# SecureScan threat model

## Scope and assets

This model covers the browser, Next.js server, WSO2 Identity Server and API
Manager, Ballerina integration API, Go scanner, and PostgreSQL. The primary
assets are authenticated identity and roles, access/session credentials,
allowed-target policy, scan authorization and results, scanner egress, and the
immutable audit trail.

The system assumes that administrators approve only targets for which written
authorization exists. An allowlist entry is policy data, not proof of ownership.

## Trust boundaries

```text
Untrusted browser
  | encrypted session / OAuth access token
  v
Next.js server ----> WSO2 Identity Server
  | bearer token
  v
WSO2 API Manager
  | validated identity + exact scopes + protected shared secret
  v
Ballerina API
  | parameterized SQL             | internal pinned-address request
  v                               v
PostgreSQL                    Go scanner ----> authorized public targets
```

1. The browser cannot assert identity headers. Next.js discards them and builds
   upstream identity only from the sealed server session.
2. API Manager authenticates tokens, enforces scopes/throttling, and is the
   intended public API entry point.
3. Ballerina trusts identity headers only with the configured Gateway secret,
   matches application roles exactly, and independently enforces ownership and
   administrator authorization.
4. PostgreSQL is the source of durable jobs, target policy, and audit events.
5. The Go service is internal and has privileged network egress. Production
   requests require the exact address set authorized by Ballerina.

The shared Gateway secret is meaningful only with network isolation. It must be
random, stored outside source control, rotated with the Gateway configuration,
and never exposed to browsers or logs.

## Threats and controls

| Threat | Primary controls | Automated evidence | Residual requirement |
| --- | --- | --- | --- |
| Forged user/admin identity | Encrypted HttpOnly session, token validation, discarded browser identity headers, Gateway secret, exact role names | Proxy spoofing tests; Ballerina secret/role/lookalike tests | Verify live WSO2 claims and rotate secrets |
| Horizontal scan access | Owner stored on jobs/results/audits; owner predicate on detail/history; admin positive path is separate | Authorization helper tests; rollback-only database owner fixtures | Run authenticated two-user DB/API acceptance on the target runtime |
| Administrator privilege escalation | `/admin` route guard, `securescan:admin` scope, `requireAdmin` on every admin resource; auth cannot be disabled in deployable topology | Route, role-lookalike, auth-configuration tests | Verify normal-user `403` through API Manager |
| SSRF / unauthorized targets | Enabled exact hostname/IP/CIDR policy, port containment, all-answer unsafe-address checks, Go special-use address denylist | Ballerina and Go unsafe IPv4/IPv6/multi-answer tests; DB policy fixtures | Administrators must validate legal authorization before creating policy |
| DNS rebinding / TOCTOU | Resolution at admission and dispatch; Ballerina passes pins; Go compares its current DNS set and dials pins only | Public-to-private and public-to-different-public tests; exact multi-answer/dial tests | DNS can fail closed and require a retry; no availability guarantee |
| Work amplification / denial of service | 1,000 ports, at most 16 addresses, per-scan semaphore, per-owner and process-wide active limits, request/time bounds, APIM throttling | Port/address, concurrency, active-limit, request-size and throttling-script tests | Validate live quota recovery and capacity assumptions |
| Audit omission or tampering | Lifecycle/policy mutation and audit insert share transactions; constrained action/outcome/metadata; unique lifecycle events; FK retention | Database rollback, duplicate, metadata, successful/blocked sequence fixtures | Auth failures and reads remain operational logs, not durable audit rows |
| Secret or diagnostic disclosure | Server-only configuration, bounded encrypted sessions, safe envelopes/failure codes, constrained audit metadata | Proxy/header and safe-error tests | Run secret scanning and production log review before release |

## DNS pinning invariant

For hostname work, the set Ballerina authorizes at dispatch is included in the
internal request. Go rejects a missing, duplicate, oversized, noncanonical,
unsafe, or DNS-mismatched set. Once admitted, the asynchronous scanner dials
only those IPs; it never resolves the hostname again. The public job and result
continue to retain the original hostname for attribution.

At most 16 distinct addresses are accepted. Together with the 1,000-port hard
limit, one job can attempt at most 16,000 address/port combinations.

## Deliberate test-only modes

- Ballerina authentication and target-policy bypasses work only with the fixed
  `securescan-api-test` service and mock scanner URL.
- Go unpinned/private-target operation requires
  `SCANNER_ISOLATED_DEVELOPMENT=true` and forces the listener to
  `127.0.0.1:8081`.

These modes are not production features. Startup fails if their constraints are
not satisfied.

## Audit boundary

PostgreSQL durably audits applied scan lifecycle and allowed-target mutations.
Rejected authentication, forbidden reads, and administrator read-only access are
security logs rather than durable `audit_logs` events. Deployment logging must
retain Gateway, Next.js, Ballerina, and scanner correlation IDs so those denials
can be investigated without placing secrets or raw request data in PostgreSQL.

## Checkpoint decision

No known critical authorization or target-control defect remains after Day 33.
Container/deployment work must still wait for the live two-user, administrator,
DNS-change, throttling, and PostgreSQL audit checklist in the Day 33 runbook to
pass on the intended local runtime.
