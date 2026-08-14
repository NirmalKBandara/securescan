# Day 25: scan ownership and API authorization

Day 25 completes the authenticated ownership boundary between Next.js and the
Ballerina API. A scan owner is never accepted from a browser request body.
Next.js reads the validated encrypted session and forwards identity through one
of two server-only paths:

- `direct`: the local Next.js proxy adds the subject, exact application roles,
  and a shared gateway secret before calling loopback-only Ballerina.
- `gateway`: the proxy sends the WSO2 access token to API Manager. API Manager
  validates the token, removes any caller-supplied identity headers, and adds
  the trusted subject and roles before calling Ballerina.

The trusted backend contract uses `X-SecureScan-Subject`,
`X-SecureScan-Roles`, and `X-SecureScan-Gateway-Secret`. The secret must contain
at least 32 characters, must remain server-side, and must be independently
managed outside local development. Direct public access to Ballerina is not a
supported deployment topology.

## Authorization rules

| Operation | `securescan-user` | `securescan-admin` |
| --- | --- | --- |
| Create scan | Created with caller subject | Created with caller subject |
| Read scan by ID | Own scan only | Any owner's scan |
| List history | Own history only | Own history or a selected `ownerSubject` |

Missing or invalid gateway authentication returns `401
AUTHENTICATION_REQUIRED`. An authenticated identity without an exact SecureScan
role, or a normal user selecting another owner, receives `403 FORBIDDEN`.
Unauthorized detail access resolves as `404 SCAN_NOT_FOUND` because the owner
predicate is part of the database lookup and does not reveal whether another
user's identifier exists.

The authenticated subject is stored in `scan_jobs.owner_subject`. The same
subject is stored as both actor and owner for `SCAN_REQUESTED`; later service
events retain the job owner while identifying the service as actor. Per-owner
active-job admission, background recovery, result completion, history, and
audit attribution all use the persisted owner rather than a development
constant.

## Frontend flow

The OIDC callback requires both an ID token and access token. Both remain inside
the encrypted HttpOnly session. Browser API calls use `/backend`; the Next.js
route handler rejects an invalid session and never forwards browser cookies,
caller identity headers, or arbitrary destinations upstream. Logout clears the
same session, so subsequent scan and history requests return `401`.

For direct local development, configure matching values:

```text
frontend: SECURESCAN_API_MODE=direct
frontend: SECURESCAN_API_GATEWAY_SECRET=<32+ character secret>
Ballerina: authenticationEnabled=true
Ballerina: gatewaySharedSecret=<same secret>
```

Day 27 changes `SECURESCAN_API_MODE` to `gateway` after the API is published.

## Acceptance evidence

- Ballerina tests cover shared-secret validation, exact user/admin roles, and
  ordinary-user cross-owner denial.
- Persistence queries include the actor subject unless the exact admin role is
  present; database verification covers two-owner isolation and audit identity.
- Frontend tests, type checking, linting, and a production build cover the
  encrypted session and server proxy boundary.
- The protected login, scan submission, history, and logout UI routes remain
  governed by the Day 23–24 session and route checks; the API now repeats the
  authorization decision instead of relying on hidden controls.

Full live multi-account evidence requires the local WSO2/API Manager runtime
described by Days 26–27. The automated checks establish the same server-side
authorization decisions without storing credentials in the repository.
