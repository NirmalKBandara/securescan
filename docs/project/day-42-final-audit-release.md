# Day 42 — Final audit and release readiness

The repository is source-complete for the planned portfolio scope, but it is
not release-evidence-complete. No release tag was created because the live
WSO2/Docker demonstration, privileged browser-admin flow, media evidence, and
external WSO2 contribution are still pending.

## Audit commands and results

The source audit passed on 21 August 2026:

```sh
./scripts/release-audit.sh source
```

It verified the MIT license link, all ten OpenAPI operation IDs, and the full
tracked-files-only clean-room gate. That gate passed Go vet/race tests/build,
47 Ballerina tests/build, 86 frontend tests, frontend lint/typecheck/production
build, documentation links/indexing, shell syntax, tracked-file secret
patterns, and whitespace.

The evidence audit was also run:

```sh
./scripts/release-audit.sh evidence
```

It correctly failed because `deployment/evidence/day-41/` does not yet contain
the ten required screenshots or `manifest.txt`. The manifest must identify the
demonstrated commit, video URL, passed privileged browser-admin flow, and a
verifiable WSO2 issue or pull-request URL.

## Definition of Done

| Core item | Repository evidence | Live evidence | Status |
| --- | --- | --- | --- |
| Authenticated WSO2 OIDC login and exact user/admin roles | OIDC/session/role code and tests | Login capture absent | Pending live proof |
| API Manager token, scope, subscription, CORS, and throttle boundary | API artifacts, policies, scripts, OpenAPI | Gateway/subscription/throttle captures absent | Pending live proof |
| Durable Ballerina scan lifecycle and safe public errors | Implementation, 47 tests, OpenAPI | Stateful Gateway flow absent | Source passed |
| Go DNS safety, pinning, limits, concurrency, and timeouts | Race-tested implementation | Authorized real scan absent | Source passed |
| PostgreSQL jobs, results, audit, and target policy | V001–V006 migrations and database CI gate | Restart-persistence capture absent | Pending live proof |
| Next.js scan, detail, history, and admin experience | 86 tests plus production build | Browser demonstration absent | Source passed |
| Target allowlist and private-range defense in depth | Ballerina/Go/database controls and tests | Real policy administration absent | Source passed |
| Six-service segmented Compose deployment | Compose/config/recovery artifacts | Healthy containers and outage recovery absent | Pending live proof |
| Automated tests and CI | Local clean-room source pass and CI definition | Current remote CI capture absent | Pending CI proof |
| Setup, architecture, API, database, security, testing, troubleshooting | Indexed maintained documents; link gate passed | README clean deployment absent | Source passed |
| Screenshots and demonstration video | Capture/redaction manifest defined | All media absent | Pending |
| Genuine WSO2 contribution | Candidate identified | No submission URL | Pending |

## Final security review

The tracked-file secret scan passed. Configuration examples contain
placeholders; ignored `.env`, certificates, WSO2 runtime state, and evidence
remain outside Git. The reviewed architecture fails closed when identity,
roles, Gateway secrets, scopes, target policy, or trusted CA configuration is
missing. The scanner retains the final DNS-set/address safety boundary.

The following residual release risks remain visible:

- The normal frontend OAuth client requests only `securescan:scan`; a separate
  privileged client or safe incremental grant must be implemented and proven
  for browser administration.
- WSO2 certificates, client/role state, API publication, subscription, and
  authorized target rules are operator-managed state and have not been
  exercised in this workspace.
- Screenshots require visual review because a text secret scanner cannot detect
  tokens, cookies, or personal data embedded in pixels.
- Dependency install reported no npm vulnerabilities, but two install scripts
  (`esbuild` and `unrs-resolver`) should be reviewed under the package
  manager's allow-scripts policy before a production deployment claim.

## Link, license, contract, and setup review

| Review | Result |
| --- | --- |
| Local Markdown links and documentation index | Passed |
| MIT `LICENSE` and README license link | Passed |
| Every Ballerina resource represented in OpenAPI | Passed: ten operations |
| Authentication, scopes, examples, errors | Documented |
| Architecture, login, deployment diagrams | Documented |
| Clean tracked-files-only source setup | Passed |
| Clean six-service README setup | Pending Docker/WSO2 host |
| Screenshot and video links | Pending |

## WSO2 contribution decision

Day 40 identified [wso2/docs-apim issue #11557](https://github.com/wso2/docs-apim/issues/11557),
an open, unassigned `good-first-issue` for broken API-key documentation images.
Its project status was already “In Progress.” Submitting a duplicate fix without
maintainer confirmation would be poor open-source practice. This workspace also
lacks a reproduced WSO2 documentation build and authorization to publish as the
user. No contribution was fabricated or claimed. The correct next action is to
confirm availability on the issue, reproduce it against the current branch,
then submit the smallest verified documentation fix and place its URL in the
evidence manifest.

## Release procedure

1. Resolve and test the privileged browser-admin OAuth flow.
2. Run the Day 37 six-service recovery gate on a Docker-capable host.
3. Capture and redact every Day 41 artifact and record the video/contribution
   URLs in `deployment/evidence/day-41/manifest.txt`.
4. Run `./scripts/release-audit.sh all` from a clean `main` checkout.
5. Confirm remote CI passes for the exact commit.
6. Only then create the annotated `v1.0.0` tag and publish it.

Until every step passes, describe the project as a source-complete local
portfolio system with pending stateful release evidence—not as a released or
production-ready service.

