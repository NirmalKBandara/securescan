# Day 30: allowed-target storage and administration API

Day 30 makes scan authorization policy administratively manageable. The API
stores exact hostnames, exact IPv4 or IPv6 addresses, and IPv4 or IPv6 CIDR
ranges in PostgreSQL. All three administration operations require the exact
`securescan-admin` application role; an authenticated ordinary user receives
`403 FORBIDDEN` before a repository function runs.

This checkpoint manages global rules. The schema retains owner-scoped columns
for a later policy phase, but the public administration API does not accept a
scope or owner supplied by a caller.

## API contract

| Method | Path | Result |
| --- | --- | --- |
| `GET` | `/api/v1/admin/allowed-targets` | List enabled rules, bounded to 1–100 rows |
| `POST` | `/api/v1/admin/allowed-targets` | Validate, normalize, store, and audit a rule |
| `DELETE` | `/api/v1/admin/allowed-targets/{targetId}` | Soft-disable and audit an enabled rule |

`GET` accepts `includeDisabled=true` for an audit-oriented view and `pageSize`
between 1 and 100. `POST` accepts this closed request shape:

```json
{
  "targetKind": "HOSTNAME",
  "target": "scan.dev.example",
  "startPort": 80,
  "endPort": 443
}
```

`targetKind` is exactly `HOSTNAME`, `IP`, or `CIDR`. Hostnames are lowercased
and must consist of valid DNS labels without wildcards or a trailing dot. `IP`
requires one exact IPv4 or IPv6 address without a prefix. `CIDR` requires an
explicit prefix. PostgreSQL validates and canonicalizes network values. The
optional ports must be supplied together and form an inclusive range from 1 to
65,535. Duplicate enabled rules return `409 ALLOWED_TARGET_EXISTS`.

Deleting a rule never removes its row. It sets `enabled=false`, updates the
database timestamp, and returns the disabled representation. Repeating the
operation, or using an unknown UUID, returns `404 ALLOWED_TARGET_NOT_FOUND`.

## Gateway setup

The API definition adds `securescan:admin`, bound only to
`securescan-admin`, and applies it to all three operations. Re-import the API
Controller project, create a new revision, and deploy it to the Gateway. The
administrator application must request `securescan:admin`; do not add this
scope to an ordinary-user application.

For an administrator token issued to that application:

```sh
export SECURESCAN_GATEWAY_TOKEN='<short-lived-redacted-token>'

curl --fail-with-body --silent --show-error \
  --header "Authorization: Bearer ${SECURESCAN_GATEWAY_TOKEN}" \
  https://localhost:8243/securescan/v1/api/v1/admin/allowed-targets

curl --fail-with-body --silent --show-error \
  --request POST \
  --header "Authorization: Bearer ${SECURESCAN_GATEWAY_TOKEN}" \
  --header 'Content-Type: application/json' \
  --data '{"targetKind":"IP","target":"192.0.2.30"}' \
  https://localhost:8243/securescan/v1/api/v1/admin/allowed-targets
```

Use documentation ranges or infrastructure the operator owns during setup.
An allowed-target entry grants policy eligibility; it is not evidence that a
third-party target is authorized for scanning.

## Transactional audit guarantees

Creation commits `allowed_targets` and `ALLOW_TARGET_CREATED` together.
Disable commits the state change and `ALLOW_TARGET_DISABLED` together. A
failed audit insert rolls back the paired policy change. Administrative events
must contain:

- `actor_type=ADMIN` and the authenticated `actor_subject`;
- the database-generated `occurred_at` timestamp;
- the request correlation UUID and affected `allowed_target_id`;
- allowlisted metadata describing the target kind/value or disabled state.

Database constraints reject non-admin administrative events, unsafe metadata,
duplicate create/disable events, and hard deletion of an audited target. Audit
rows never contain access tokens, gateway secrets, request headers, or raw
credentials.

## Acceptance and verification

With PostgreSQL migrated and seeded, test one ordinary token and one
administrator token:

1. Confirm the ordinary token receives `403` for list, create, and disable.
2. Create a hostname, an exact IPv4 or IPv6 address, and a CIDR as the admin.
3. List them, disable one, and list with `includeDisabled=true`.
4. Query `audit_logs` and confirm actor, action, target ID, request ID, and
   timestamp for every change.
5. Confirm a duplicate enabled rule returns `409` and an already-disabled rule
   returns `404` without creating an audit event.

Repository checks:

```sh
./database/scripts/migrate.sh up
./database/scripts/seed.sh
./database/scripts/verify.sh

cd ballerina-api
JAVA_HOME=/usr/lib/jvm/java-21-openjdk bal test

cd ../frontend
npm test
npm run typecheck
npm run lint
```

The automated database verification uses rollback-only fixtures to prove all
three target kinds, exact-IP host masks, admin attribution, soft disable, and
audit foreign-key retention. Live WSO2 role/scope evidence still requires a
Docker-capable host and must be captured before closing Issue #14.
