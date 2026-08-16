# Day 33: security checkpoint

Day 33 tests SecureScan's authorization, target-control, resource-limit, and
audit boundaries before containerization. The review found and fixed two
blocking design defects: deployable Ballerina configurations could disable
authentication, and a hostname was resolved again after Ballerina's policy
decision without pinning the authorized address set.

## Findings fixed

### Configuration-based administrator escalation

When authentication was disabled, Ballerina's development identity behaved as
an administrator. Startup now permits that behavior only for the fixed isolated
contract-test service and mock scanner. Production-like configurations fail
closed. Exact role checks reject case changes, prefixes, suffixes, and unrelated
role names.

The Next.js direct-development proxy also proves that browser-provided subject,
role, and Gateway-secret headers are ignored and replaced with values derived
from the encrypted session and server configuration.

### DNS authorization-to-dial gap

Ballerina now sends its dispatch-time address set in the internal scanner
request. Go requires that set outside isolated development, validates every
address, resolves the hostname once to require an exact set match, then stores
and dials only the pins. A public-to-private or public-to-different-public DNS
change fails before job execution.

Go additionally rejects carrier-grade NAT, protocol-assignment, benchmarking,
documentation, reserved, discard-only, ORCHID, and IPv6 documentation ranges.
IPv4-mapped IPv6 addresses are unmapped before classification. Both services
limit one target to 16 distinct addresses.

## Security checklist

| Control | Repository evidence | Result |
| --- | --- | --- |
| Horizontal access | Exact owner predicates, cross-owner denial/admin helper tests, database owner/result fixtures | Pass; live two-user check pending |
| Administrator escalation | Exact-role/lookalike tests, test-only auth downgrade, route guard, proxy spoofing test, API `requireAdmin` | Pass; live WSO2 scope check pending |
| Unsafe targets | Ballerina and Go IPv4/IPv6, metadata, special-use, mapped-address, and mixed-answer cases | Pass |
| DNS changes | Admission/dispatch resolution, exact Ballerina→Go pin contract, public/private and changed-public tests, pin-only dial test | Pass |
| Port/address limits | 1,000 ports and 16 addresses; request/time/concurrency bounds | Pass |
| Concurrency limits | Go semaphore/global active limit and Ballerina per-owner transactional admission | Pass; DB race exercise pending |
| Audit completeness | Successful/blocked/failure lifecycle constraints, target-policy events, attribution, uniqueness, rollback and redaction fixtures | Pass; live runtime sequence pending |

## Automated commands

```sh
cd scanner-engine
go test ./...
go test -race ./...
go vet ./...

cd ../ballerina-api
JAVA_HOME=/usr/lib/jvm/java-21-openjdk bal test

cd ../frontend
npm test
npm run typecheck
npm run lint
```

The checkpoint result is 47 passing Ballerina tests, the complete Go test and
race suites, clean Go vet, and 83 passing frontend tests with clean typecheck and
lint.

## Live acceptance matrix

On a host with PostgreSQL and the WSO2 services available:

1. Create Alice, Bob, and administrator identities.
2. Confirm Alice cannot retrieve Bob's detail/history/results by ID, owner
   filter, or cursor manipulation; confirm the administrator positive path.
3. Call every admin scan/audit/usage/target endpoint with a missing token,
   ordinary user, admin-role lookalikes, and a real administrator.
4. Exercise an allowed public test target, a disabled rule, unsafe IPs, mixed
   DNS answers, and a controlled DNS set change. Confirm no rejected request
   reaches the dial function.
5. Exercise 1,000 and 1,001 ports, 16 and 17 addresses, per-owner concurrency,
   global concurrency, and Gateway throttling/recovery.
6. Query audit rows for requested, started, completed, failed, admission-blocked,
   dispatch-blocked, and policy-change sequences. Confirm actor/owner/request
   attribution and absence of secrets/raw diagnostics.

Do not begin deployment work if any critical item fails. This environment lacks
a PostgreSQL server, Docker runtime, and live WSO2 topology, so the live matrix
is recorded honestly as pending rather than fabricated.

## Known environment limitation

`next build` compiles and typechecks under the installed Node 26.3.1, then its
Next.js 16.3 static-generation worker exits silently at page 4/10. The failure
also occurs with a single worker, so no worker-count workaround was retained.
Rerun the production build on the documented Node LTS environment during the
clean-room checkpoint.

## Related policy

The trust-boundary and STRIDE-style control mapping is in
[`threat-model`](threat-model.md). Legal scope, approval, stop-work, and data
handling requirements are in [`authorized-use-policy`](authorized-use-policy.md).
