# Day 24 — Protected routes and role authorization

Day 24 completes the frontend WSO2 integration by turning the Day 23 identity
session into an enforced application-access policy. Authentication and roles
now determine which SecureScan routes and navigation items a user can reach.

## Access matrix

| Identity | Dashboard, scans, history | Administration |
| --- | --- | --- |
| No valid session | Redirect to login with a safe return path | Redirect to login with a safe return path |
| Authenticated without a SecureScan role | Forbidden | Forbidden |
| `securescan-user` | Allowed | Forbidden |
| `securescan-admin` | Allowed | Allowed |

Role values are exact and case-sensitive. The configured `OIDC_ROLE_CLAIM`
defaults to `groups`; the callback also understands WSO2's common `groups`,
`roles`, `role`, and `http://wso2.org/claims/role` shapes. Only
`securescan-user` and `securescan-admin` survive normalization into the
encrypted session. Unrelated provider roles never grant application access.

## Enforcement points

Next.js 16 `proxy.ts` validates the encrypted session and applies the matrix to
`/dashboard`, `/history`, `/scans/*`, and `/admin`. Missing, expired, malformed,
or cryptographically invalid cookies are treated as anonymous and cleared on
the authentication redirect. Authenticated users without sufficient roles go
to the accessible `/forbidden` page rather than entering a redirect loop.

The admin Server Component repeats the `securescan-admin` check before
rendering. Proxy is the early navigation gate; it is not the sole security
check for privileged server behavior. Any future admin Server Action or Route
Handler must independently call the same authorization helpers.

The header exposes ordinary navigation only to SecureScan members and renders
the Admin item only for administrators. Sign-out remains available to every
authenticated identity, including one that reaches the forbidden page.

`/login`, `/auth/*`, and `/forbidden` are public by design. `/ui-preview`
remains an explicitly backend-free development review surface and is not part
of the authenticated product route set; production packaging should omit or
separately restrict it.

## Verification

Run the complete frontend gate:

```sh
cd frontend
npm ci
npm test
npm run typecheck
npm run lint
npm run build
```

The role and route tests cover anonymous, outsider, user, and administrator
decisions; exact role normalization; custom role-claim selection; ordinary
routes; and the admin boundary. Session tests separately cover expiry and
tamper detection.

After starting the built frontend, anonymous requests must behave as follows:

```sh
curl --head http://localhost:3000/dashboard
curl --head http://localhost:3000/admin
curl --head http://localhost:3000/login
curl --head http://localhost:3000/forbidden
```

The first two return 307 with encoded same-origin return paths; the public
pages return 200. Complete a browser login with one test identity for each row
of the matrix and verify both direct navigation and the visible header links.

## Remaining trust boundary

Day 24 protects frontend pages; it does not convert the Ballerina API into an
OIDC resource server. The Next.js `/backend` rewrite, direct Ballerina listener,
and development owner subject remain pre-auth boundaries. Secure ownership
requires API Manager policy, validated access-token propagation, and Ballerina
issuer/audience/scope enforcement in later checkpoints. Never treat a frontend
cookie or client-supplied identity header as backend proof of identity.
