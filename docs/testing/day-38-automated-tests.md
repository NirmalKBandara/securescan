# Day 38 — Automated test and CI checkpoint

Day 38 turns the repository's component suites into one required, repeatable
continuous-integration gate. Pull requests and pushes to `main`, `feature/**`,
and `docs/**` run independent jobs so failures identify the affected boundary
without hiding later checks behind an earlier component failure.

## Automated coverage

| Job | Required checks |
| --- | --- |
| Go scanner | `go vet`, race-enabled unit/integration tests, and build |
| Ballerina API | service and DNS-pinning tests, then build |
| Next.js frontend | 86 Vitest tests, ESLint, strict typecheck, production build |
| PostgreSQL | all six migrations, development seed, schema/constraint behavior |
| Repository | shell syntax, local documentation links, tracked/history credential patterns, `git diff --check` |

The workflow grants read-only repository access, cancels superseded runs for
the same ref, uses lockfile/module-aware dependency caches, and gives the
database job a disposable PostgreSQL 16 service. No application credential,
local `.env`, retained volume, or authorized network target is required.

## Run locally

Install Go 1.26.4, Java 21 with Ballerina 2201.13.4, and Node.js 20 or newer.
Install the frontend dependencies with `npm ci` after a clean checkout. Then
run the complete component gate from the repository root:

```sh
./scripts/verify.sh
```

Run one boundary while developing:

```sh
./scripts/verify.sh go
./scripts/verify.sh ballerina
./scripts/verify.sh frontend
./scripts/verify.sh repository
```

Database verification runs in CI against an empty disposable service. For the
equivalent Docker-backed local check, start PostgreSQL, then use the maintained
database commands:

```sh
./database/scripts/migrate.sh up
./database/scripts/seed.sh
./database/scripts/verify.sh
```

## Gate boundaries

This fast gate proves source-level behavior, builds, migration correctness, and
repository hygiene. It does not claim that WSO2 applications, subscriptions,
TLS trust, browser login, or an authorized real scan are configured. Those
stateful checks remain in the
[Day 37 Compose recovery gate](../deployment/day-37-compose-recovery.md), which
must run on a Docker-capable host before deployment.

## Verification status on this workstation

The repository checks, Go vet/race tests/build, all 86 frontend tests, lint,
typecheck, and production build pass. Ballerina compiles with Java 21, but its
test runtime cannot open a LAN socket in this restricted workspace; the new CI
job runs it on an unrestricted GitHub runner. PostgreSQL and the full Compose
recovery gate require Docker, which is not installed here. No unavailable test
is reported as passing.
