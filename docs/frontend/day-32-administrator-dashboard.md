# Day 32: administrator dashboard

Day 32 replaces the administration placeholder with an authenticated management
workspace. An administrator can review scans across users, filter by owner and
status, inspect immutable audit events, see basic platform counts, and create or
disable allowed-target rules without leaving the SecureScan UI.

## Security boundary

The page and API are independently protected:

- Next.js route authorization requires an encrypted session containing the
  exact `securescan-admin` application role before `/admin` is rendered.
- The backend proxy unseals identity and the access token only from the
  encrypted HttpOnly session cookie; client-side JavaScript cannot read them.
- API Manager binds every `/api/v1/admin/*` operation to the
  `securescan:admin` scope.
- Ballerina authenticates the trusted Gateway headers and calls `requireAdmin`
  before validating filters or querying PostgreSQL.

The browser route is a usability boundary. Ballerina's role check is the real
authorization boundary, so hiding navigation or calling an endpoint directly
cannot grant administrator access. Ordinary users receive `403 FORBIDDEN`.

## Administrator API

### Scan review

```http
GET /api/v1/admin/scans?pageSize=50&ownerSubject=<subject>&status=blocked
```

Both filters are optional. `status` accepts `queued`, `running`, `completed`,
`failed`, or `blocked` case-insensitively. `pageSize` is bounded from 1 to 100.
Results are ordered by newest creation time and ID and include the owner plus a
safe failure code, allowing blocked and failed jobs to be reviewed directly.

### Audit review

```http
GET /api/v1/admin/audit-logs?pageSize=50
```

The endpoint returns the newest events first. It exposes only the constrained
audit fields and metadata already protected by PostgreSQL checks: actor type and
subject, owner, action, outcome, request and resource identifiers, timestamp,
and action-specific safe metadata. It does not expose credentials, headers,
request bodies, raw scanner errors, or DNS answers.

### Usage summary

```http
GET /api/v1/admin/usage
```

One aggregate query returns distinct owners, total scans, lifecycle counts, and
the number of enabled target policies. These are operational counts, not a
billing or analytics system.

### Allowed-target management

The dashboard uses the Day 30 endpoints:

```http
GET    /api/v1/admin/allowed-targets?includeDisabled=true
POST   /api/v1/admin/allowed-targets
DELETE /api/v1/admin/allowed-targets/{targetId}
```

The UI supports exact hostname, exact IP, and CIDR rules plus an optional paired
port range. It rejects an incomplete or reversed range before submission, while
the API remains authoritative. “Disable” is intentionally a soft delete;
confirmation explains that immutable audit history is retained.

## Interface behavior

The responsive dashboard provides:

- usage cards for users, scans, active work, blocked/failed work, and policies;
- all-user scan rows with owner and status filters;
- explicit blocked and failed status/failure presentation;
- allowed-target creation, disabled-state visibility, and confirmed disable;
- the latest audit events with actor, owner, action, outcome, and UTC time; and
- accessible table captions, labels, focusable overflow regions, live loading
  and success notices, and alert semantics for failures.

Requests go through the existing same-origin `/backend` route. Access tokens and
the Gateway shared secret are available only to server-side route code after
the session cookie is unsealed. The default ordinary frontend client requests
only `securescan:scan`, while a safe `/admin` login destination selects a
separate privileged client that also requests `securescan:admin`. The selected
client kind is sealed into the OIDC transaction and API Manager still requires
the administrator scope for every protected operation.

## Verification

Run the frontend checks:

```sh
cd frontend
npm test
npm run typecheck
npm run lint
```

The component tests cover cross-user blocked-scan visibility, owner/status
filter forwarding, bounded target creation, and rejection of an incomplete
port policy. Existing authorization tests cover ordinary-user denial for the
administration route.

Run the Ballerina contract suite:

```sh
cd ballerina-api
JAVA_HOME=/usr/lib/jvm/java-21-openjdk bal test
```

The service suite verifies the shared authentication and exact administrator
role boundary used by every admin resource. PostgreSQL queries are parameterized
and all collection bounds are enforced before database access.

## Acceptance result

The repository checkpoint satisfies the UI, Ballerina, and API contract
requirements: administrator behavior is implemented and a normal user is
rejected by the route and API authorization layers. The separate privileged
client flow is source-tested; its live WSO2 registration and evidence remain
required before claiming the end-to-end admin dashboard path is deployable.
