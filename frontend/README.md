# SecureScan frontend

The Day 28 frontend is a Next.js 16 App Router application with strict TypeScript,
plain CSS design tokens, an accessible application shell, a typed boundary for
the Ballerina public API, reusable scan interface components, and validated scan
submission.

## Requirements

- Node.js 20.9 or newer
- npm 10 or newer

## Setup

```bash
cp .env.example .env.local
npm install
npm run dev
```

Open `http://localhost:3000`. `NEXT_PUBLIC_API_BASE_URL` is required in every
environment; the example uses the same-origin `/backend` path. The authenticated
Next.js route sends that traffic to the server-only `API_MANAGER_GATEWAY_URL`.
OIDC requires the server-only `APP_BASE_URL`,
`OIDC_ISSUER`, `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`, and
`AUTH_SESSION_SECRET` values shown in `.env.example`; real credentials belong
only in the ignored `.env.local` file.
Set `OIDC_ROLE_CLAIM` to the WSO2 claim that carries exact
`securescan-user` / `securescan-admin` values; it defaults to `groups`.
`OIDC_SCOPES` must include both `openid` and the API's `securescan:scan` scope.

`/backend` is an authenticated route-handler proxy rather than a transparent
rewrite. In `direct` mode it derives trusted identity headers from the encrypted
session and calls loopback-only Ballerina with `SECURESCAN_API_GATEWAY_SECRET`.
In `gateway` mode it sends the session's access token to the published API
Manager context. This is the default and fails closed if
`API_MANAGER_GATEWAY_URL` is absent. `BALLERINA_API_BASE_URL` is read only when
the explicit development fallback `SECURESCAN_API_MODE=direct` is selected.
Browser-provided identity headers and cookies are never passed to Ballerina.
Non-envelope API Manager errors are converted to safe public error envelopes so
the existing accessible alert remains useful for authentication, scope, and
throttling failures.

## Authentication

`/auth/login` starts WSO2 Authorization Code with PKCE. `/auth/callback`
validates the state, nonce, PKCE verifier, and signed ID token before issuing a
bounded encrypted HttpOnly application session. `/auth/logout` accepts POST,
clears local authentication state, and continues through WSO2 logout when the
provider is reachable. The site header reflects the validated session without
exposing provider tokens to client-side JavaScript.

`proxy.ts` protects dashboard, scan, history, and admin routes. Both application
roles can use ordinary scan routes, while only `securescan-admin` can enter
`/admin`; the admin page repeats that check server-side. Identities without an
application role receive `/forbidden`. This frontend gate does not replace
API Manager or Ballerina access-token validation.

For local WSO2, trust the exported development certificate with
`NODE_EXTRA_CA_CERTS`; do not disable Node TLS validation globally. Use HTTPS
and managed secrets outside local development.

## Routes

- `/login` — identity-provider entry page
- `/dashboard` — scan overview and primary action
- `/scans/new` — validated scan submission to the Ballerina public API
- `/scans/[id]` — scan status/results destination
- `/history` — durable scan history with status filtering and UTC timestamps
- `/admin` — administrator controls destination
- `/forbidden` — accessible insufficient-role outcome
- `/ui-preview` — backend-free Day 17 component and state review surface

The new-scan, scan-detail, and history pages use the shared `ScanForm`, `ScanStatus`, and
`ResultsTable` components. `ScanForm` uses React Hook Form and Zod to validate
target syntax, port boundaries and ordering, and explicit authorization before
calling `scansApi.create`. Accepted jobs navigate to `/scans/{id}`; history
loads durable newest-first jobs, filters them locally by lifecycle status, and
links every row back to its detail page. Public API
errors and correlation request IDs render in an accessible alert.

`/ui-preview` uses deterministic mock data to show
queued, running, completed, failed, blocked, loading, error, populated-result,
and empty-result states. Its form is deliberately disabled so the preview never
creates a real scan.

## Reusable components

- `ScanForm` — labeled target, port range, and authorization controls
- `ScanStatus` and `StatusBadge` — lifecycle presentation with text and color
- `ResultsTable` — semantic desktop table and responsive mobile result cards
- `ErrorMessage` — alert feedback with optional correlation request ID
- `LoadingState` — text and motion-based progress feedback

Mock data lives in `lib/mocks/scans.ts` and is presentation-only. Components do
not call the backend directly; later pages should continue to use `scansApi`.

## API client

`lib/api/types.ts` mirrors `docs/api/ballerina-public-api.md`, including stable
success/error envelopes, lifecycle states, results and keyset history. Use the
single `scansApi` export instead of calling configured URLs from components.
The boundary preserves public request IDs on `SecureScanApiError` for support.

## Quality checks

```bash
npm test
npm run typecheck
npm run lint
npm run build
```

See `docs/frontend/day-20-history-checkpoint.md` for history behavior, the
same-origin service boundary, integration checks, and test coverage.
OIDC application registration and exact callback settings are documented in
`docs/identity/day-22-wso2-oidc-client.md`.
The complete login and session behavior is documented in
`docs/identity/day-23-oidc-login.md`.
The role matrix and protected route behavior are documented in
`docs/identity/day-24-route-authorization.md`.
The API Manager application, subscription, scope, CORS, and live browser checks
are documented in `docs/gateway/day-28-gateway-routing.md`.

Do not commit `.env.local`, tokens, or identity-provider secrets. Only
`NEXT_PUBLIC_*` values intended for browsers belong in this application.
