# SecureScan portfolio and interview notes

Use wording that matches the evidence available at the time. Do not replace
“implemented” with “deployed” until the Day 42 release audit passes.

## CV wording — current source-complete state

> Built SecureScan, a defense-in-depth authorized TCP scanning portfolio
> platform using Next.js, WSO2 Identity Server/API Manager, Ballerina, Go, and
> PostgreSQL; implemented OIDC/PKCE sessions, scope and role enforcement,
> durable asynchronous jobs, DNS-rebinding-resistant address pinning,
> allowlisted targets, audit trails, segmented Docker Compose artifacts, and
> cross-stack automated tests.

> Verified the codebase from a tracked-files-only clean checkout with Go race
> tests, 47 Ballerina tests, 86 frontend tests, production builds, migration
> checks in CI, documentation integrity checks, and secret-pattern scanning;
> documented remaining WSO2/Docker runtime evidence transparently.

After the full release audit passes, the second bullet may instead name the
demonstrated login-to-scan-to-admin flow, restart persistence, throttling, and
the tagged version.

## Thirty-second explanation

SecureScan is an authorized-use TCP connect scanner designed to show security
boundaries rather than scanning novelty. WSO2 authenticates users and governs
the public API, Ballerina owns validation, authorization, durable lifecycle,
and audit, Go performs bounded network work with final DNS safety checks, and
PostgreSQL stores policy and results. The interesting design choice is that no
single upstream check is trusted: Gateway policy, Ballerina authorization, and
Go's resolve-validate-pin-dial sequence all fail closed independently.

## Interview questions

### Why Ballerina and Go?

Ballerina expresses the integration/API/persistence workflow and stable public
contract. Go owns concurrent TCP work and the last network-safety decision.
Keeping the scanner internal prevents public identity and orchestration logic
from leaking into the network engine.

### How do you prevent SSRF and DNS rebinding?

Targets must match an enabled exact hostname, IP, or CIDR policy with complete
port-range containment. Ballerina rejects private and special-use answers,
then passes the complete authorized address set to Go. Go resolves again,
requires the same set, rechecks every address, and dials only those pins.

### Why is `202 Accepted` reliable?

Ballerina commits the public queued job and audit event before returning. A
durable dispatch lease and the public UUID as an idempotency key allow safe
reconciliation after ambiguous timeouts or restarts without duplicate jobs.

### What does API Manager add if Ballerina authorizes again?

API Manager owns token validation, scopes, subscriptions, CORS, quotas, and
the external API lifecycle. Ballerina remains responsible for domain
authorization, ownership, exact roles, and target policy. Repeating the
critical checks limits the impact of a mistaken Gateway policy.

### How are secrets and tokens handled?

The browser receives only an encrypted HttpOnly session cookie. Next.js
unseals the session server-side and sends the access token to API Manager.
Examples contain placeholders, runtime secret/certificate files are ignored,
and tests reject missing or weakened security configuration.

### What would you improve next?

First complete the privileged browser-admin grant and stateful WSO2/Docker
release evidence. After that, improve operational observability and automated
WSO2 provisioning without adding new scanner features before the core release
is demonstrably reproducible.

### What is the most important current limitation?

The source gates pass, but this workspace has not produced the live WSO2 login,
Gateway, throttling, restart-persistence, and recovery evidence. The ordinary
browser client also lacks a completed administrator-scope grant. Those are
explicit release blockers, not hidden follow-up tasks.

