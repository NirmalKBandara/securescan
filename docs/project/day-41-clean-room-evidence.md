# Day 41 — Clean-room test and portfolio evidence

Day 41 separates reproducible source evidence from the stateful six-service
demonstration. This prevents a source-only pass from being presented as proof
that WSO2, API Manager, PostgreSQL, and the browser flow are configured.

## Clean-room source result

On 21 August 2026, commit `de1ac7c` passed the complete source gate from a
temporary archive containing only tracked files:

```sh
./scripts/verify-clean-room.sh all
```

The script creates a temporary checkout from committed `HEAD`, installs
frontend dependencies with `npm ci`, and runs the Go, Ballerina, frontend, and
repository gates. Observed results were:

| Gate | Result |
| --- | --- |
| Go vet, race tests, and build | Passed |
| Ballerina tests and build | 47 passed; build passed |
| Frontend tests | 86 passed across 13 files |
| Frontend lint, typecheck, and production build | Passed |
| npm audit during clean install | 0 vulnerabilities reported |
| Documentation, shell syntax, secret patterns, whitespace | Passed |

The temporary checkout is deleted on exit. Use `repository`, `go`,
`ballerina`, or `frontend` instead of `all` to isolate one gate. The command
requires a clean source worktree so its result cannot omit uncommitted files.

## Stateful demonstration status

The current workspace does not provide a configured Docker/WSO2 runtime.
Therefore these acceptance items are **pending**, not failed and not claimed as
complete:

- browser login through WSO2 Identity Server;
- an authorized scan through the API Manager Gateway;
- persisted history after service restart;
- administrator scan, usage, audit, and allowed-target review;
- API Manager subscription throttling;
- all six containers healthy and internal services unpublished;
- dependency-outage and recovery behavior;
- final screenshots and demonstration video.

Run the [Day 37 recovery procedure](../deployment/day-37-compose-recovery.md)
before capturing evidence. Do not use direct-development authentication or a
direct Ballerina URL as a substitute for the Gateway path.

## Evidence manifest

Store local captures in ignored `deployment/evidence/day-41/`. Keep the video
outside Git and record its durable portfolio URL only after upload. Use names
that match this manifest.

| File or link | Required proof | Status |
| --- | --- | --- |
| `01-login.png` | WSO2 login and successful return to protected dashboard | Pending |
| `02-apim-api.png` | Published SecureScan API, v1 context, and scoped operations | Pending |
| `03-apim-subscription.png` | Subscribed application and the applicable user/admin plan | Pending |
| `04-scan-request.png` | Authorized target and bounded port submission | Pending |
| `05-scan-result.png` | Completed scan with address, port states, and timestamps | Pending |
| `06-history-after-restart.png` | Same completed scan after Ballerina/PostgreSQL restart | Pending |
| `07-admin-review.png` | Cross-user scans, usage, audit events, and target policy | Pending |
| `08-throttled-response.png` | Gateway `429` with safe response and no backend bypass | Pending |
| `09-containers.png` | Six healthy services and published-port boundaries | Pending |
| `10-ci.png` | Passing Go, Ballerina, frontend, database, and repository jobs | Pending |
| Portfolio video URL | Login → scan → result/history → admin review in 3–5 minutes | Pending |

For each artifact, record the commit SHA, UTC capture time, WSO2 product
versions, browser version, and test target in a local `manifest.txt`.

## Capture and redaction rules

- Use only a target you own or have explicit permission to scan.
- Never capture access/refresh tokens, authorization codes, client secrets,
  cookies, shared Gateway secrets, database passwords, or `.env` contents.
- Crop or blur personal email addresses, tenant/user identifiers, machine
  names, and unrelated browser tabs.
- Keep request IDs and public scan IDs when safe; they demonstrate correlation.
- Capture the Gateway URL or API Manager view so the evidence proves the
  intended route rather than a direct backend call.
- Show the throttle response and recovery without publishing reusable
  credentials or target infrastructure details.

## Demonstration script

1. Show all six healthy containers and the loopback-only published ports.
2. Sign in as a normal user through WSO2 Identity Server.
3. Submit an acknowledged, allowlisted scan through the frontend.
4. Follow queued/running state to completion and open the result/history view.
5. Restart the application dependency prescribed by the recovery runbook and
   show that the completed job remains.
6. Sign in through the verified privileged client/grant, open administration,
   and show usage, audit, scans, and target policy.
7. Trigger the documented test subscription limit and show Gateway `429`.
8. End on the passing CI checks for the exact demonstrated commit.

If the privileged browser-admin OAuth limitation is still unresolved, stop
before step 6 and state that limitation in the recording; do not splice a
direct API call into the browser flow and present it as complete.

