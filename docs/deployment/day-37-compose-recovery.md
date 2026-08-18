# Day 37 — Compose integration and recovery checkpoint

Day 37 provides one reproducible gate for cold-start ordering, empty application
database bootstrap, two login-to-results flows, retained results, dependency
failure behavior, and recovery. It uses the existing Identity Server and API
Manager volumes but gives PostgreSQL and all networks unique recovery-run names,
so it cannot erase the normal application database.

## Prerequisites

- Docker Engine and the Docker Compose plugin are installed.
- The normal SecureScan Compose stack is stopped so its loopback ports are free.
- `deployment/.env` passes `deployment/validate-config.sh` and contains the
  client values for the retained WSO2 development state.
- The one-time WSO2 registration/publication steps in the Day 36 runbook are
  complete, including trusted TLS names and frontend CA trust.
- An enabled allowlist rule covers a target you own and are authorized to scan.

WSO2 browser endpoints must retain the registered `localhost` callback and
logout URLs. Container-to-container URLs must use certificates whose SANs match
`identity-server` and `api-manager`; mount the issuing development CA into the
frontend and set `NODE_EXTRA_CA_CERTS` to that in-container PEM path. A callback
or discovery document that sends the browser to a Compose-only hostname is a
configuration failure. Disabling TLS verification is not an acceptable fix.

## Run the checkpoint

```sh
cp deployment/.env.example deployment/.env  # only if it does not exist
# Replace every placeholder and preserve the existing WSO2 client values.
deployment/validate-config.sh deployment/.env
deployment/verify-compose-recovery.sh
```

The default driver pauses at the browser checks. Type `READY` after reviewing
the WSO2 setup, paste the completed scan UUID for each of two real flows, and
type `SAFE` only after each dependency outage produces a bounded public error
without a stack trace, token, credential, or internal URL.

For automated browser/API execution, set `SECURESCAN_RECOVERY_DRIVER` to an
executable implementing this contract:

```text
driver bootstrap
driver complete-flow 1       # stdout: one completed public scan UUID
driver complete-flow 2       # stdout: one completed public scan UUID
driver dependency-down scanner-engine|postgres|api-manager|identity-server
```

The driver must return non-zero unless it observes the named condition.

## What the gate proves

| Phase | Automated assertion | Operator/driver assertion |
| --- | --- | --- |
| Cold start | all services become healthy; exact elapsed seconds recorded | WSO2 setup is usable |
| Empty PostgreSQL | six migrations exist in `schema_migrations` | — |
| End-to-end, twice | returned IDs are valid UUIDs | login, authorized submission, polling, terminal results |
| Normal restart | both scan rows still exist after `down` / `up` | retained results remain readable |
| Scanner outage | service stops and returns healthy after restart | scanner-unavailable response is safe |
| PostgreSQL outage | database stops and returns healthy | persistence failure is bounded and later recovers |
| API Manager outage | Gateway stops and returns healthy | frontend does not bypass the Gateway |
| Identity outage | Identity Server stops and returns healthy | login/session failure is safe and recovers |

API Manager health now checks both Publisher and the HTTPS Gateway listener.
Successful publication of the SecureScan revision is proven by the two real
flows rather than by treating a generic Gateway socket as API readiness.

## Evidence and cleanup

Each run writes an ignored directory under `deployment/evidence/` containing:

- `timeline.tsv` with UTC events, cold-start seconds, and restart seconds;
- initial and final Compose service snapshots;
- the two completed scan IDs used for the persistence assertion.

The recovery project is stopped automatically and only its uniquely named
PostgreSQL volume is deleted. Retained WSO2 volumes are never passed to
`down --volumes`. Set `KEEP_RECOVERY_STACK=true` only for troubleshooting; the
script prints the exact project prefix that must later be cleaned up.

## Verification status on this workstation

Shell syntax, configuration validation, secret checks, `git diff --check`, all
Go and Ballerina tests, all 86 frontend tests, lint, typecheck, and the
production frontend build pass. The recovery gate exits with a clear Docker
requirement before mutating anything because Docker is not installed on this
workstation. Consequently, no cold-start duration or live login-to-results
evidence is claimed here; run this document's gate on a Docker-capable host
before marking the live acceptance check complete.
