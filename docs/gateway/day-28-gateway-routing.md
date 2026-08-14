# Day 28: route Next.js through API Manager

Day 28 makes the published WSO2 API Manager Gateway the default upstream for
the authenticated Next.js backend-for-frontend. Browser code continues to call
the same-origin `/backend` route. The route reads the encrypted server-side
session and forwards its WSO2 Identity Server access token to
`https://localhost:8243/securescan/v1`; tokens are never exposed to client-side
JavaScript.

## Request and trust flow

```text
browser /backend request
  -> Next.js validates encrypted application session
  -> Next.js adds the unchanged Identity Server bearer token
  -> API Manager validates token, subscription, securescan:scan scope, and throttle
  -> API Manager removes caller-supplied X-SecureScan-* headers
  -> mediation adds the validated subject, roles, and backend shared secret
  -> Ballerina validates the trusted hop, role, and persisted owner
  -> Next.js returns a SecureScan success/error envelope to the browser
```

`API_MANAGER_GATEWAY_URL` is server-only. `NEXT_PUBLIC_API_BASE_URL` remains
`/backend`; setting it to the Gateway URL would expose the bearer token boundary
to browser code and is not the supported configuration.

## API Manager and Identity Server preparation

Complete the Day 27 import and deployment first. In API Manager's Admin Portal,
configure WSO2 Identity Server as a key manager for the tenant. Its issuer,
authorization, token, introspection or JWKS, user-info, and revocation values
must come from the Identity Server discovery metadata used by the frontend;
do not copy placeholder endpoints from screenshots. Enable the authorization
code grant and scope validation.

In Publisher, re-import the Day 28 API project and deploy a new revision. Verify:

- `securescan:scan` appears as an API scope and is bound only to
  `securescan-user,securescan-admin`;
- every scan operation requires `securescan:scan`;
- CORS allows only `http://localhost:3000`, with `GET`, `POST`, and `OPTIONS`;
- credentials are disabled for Gateway CORS because the supported browser path
  is the same-origin Next.js proxy;
- `securescan-identity-in` remains the inbound mediation policy;
- the production endpoint remains `http://host.docker.internal:9090`;
- the published revision is deployed to the `Default` Gateway.

For a non-local frontend, replace the local CORS origin in
`deployment/apim/securescan-api/api.yaml` with the exact HTTPS application
origin before import. Do not use `*` and do not add `/backend` or any path.

## Developer Portal application and subscription

Use the same ordinary test identity and OIDC client prepared for Days 22–23.
In Developer Portal:

1. Create or open the `SecureScanFrontend` application.
2. Select the Identity Server key manager.
3. Provision the existing frontend OIDC client as an out-of-band client, using
   the exact `OIDC_CLIENT_ID`; never commit its secret.
4. Confirm Authorization Code is allowed and the callback is exactly
   `http://localhost:3000/auth/callback`.
5. Subscribe the application to `SecureScanAPI : v1` using the intended
   development throttling policy.
6. Confirm `securescan:scan` can be granted to identities with
   `securescan-user` or `securescan-admin`, and not to an identity without an
   application role.

The subscription and the OIDC session must refer to the same recognized OAuth
client. A separate Developer Portal client-credentials token is sufficient for
Day 27 command-line checks but does not prove the Day 28 browser flow.

## Frontend configuration

Copy `frontend/.env.example` to the ignored `frontend/.env.local`, then set the
real client secret and session secret. The routing values are:

```dotenv
NEXT_PUBLIC_API_BASE_URL=/backend
SECURESCAN_API_MODE=gateway
API_MANAGER_GATEWAY_URL=https://localhost:8243/securescan/v1
OIDC_SCOPES=openid profile email securescan:scan
```

Trust the local Identity Server and Gateway development certificates using
`NODE_EXTRA_CA_CERTS`. Never set `NODE_TLS_REJECT_UNAUTHORIZED=0`. Direct mode
is an explicit development fallback only:

```dotenv
SECURESCAN_API_MODE=direct
BALLERINA_API_BASE_URL=http://127.0.0.1:9090
SECURESCAN_API_GATEWAY_SECRET=<matching-development-secret>
```

Gateway mode fails closed when `API_MANAGER_GATEWAY_URL` is absent; it never
silently bypasses API Manager by using the Ballerina URL.

## Identity, scope, and error verification

Use a short-lived test session and keep tokens out of logs and screenshots.

| Check | Required evidence |
| --- | --- |
| Bearer boundary | Browser network tools show only `/backend`; a server-side test proves the exact session access token is sent to the Gateway. |
| Scope | Login requests `securescan:scan`; the Gateway accepts that token and rejects an otherwise valid token without the scope. |
| Subject | Ballerina audit data records the authenticated Identity Server subject, not a browser header value. |
| Roles | An ordinary user can read only owned scans; an unprivileged identity is rejected; the exact admin role retains its documented access. |
| Spoofing | Caller-supplied `X-SecureScan-Subject`, `X-SecureScan-Roles`, and `X-SecureScan-Gateway-Secret` never reach Ballerina unchanged. |
| Errors | Gateway `401`, `403`, and `429` outcomes render as safe frontend alerts with a correlation request ID. |

The Next.js proxy preserves valid Ballerina envelopes. A non-JSON or
non-SecureScan Gateway response is normalized to the same public error shape,
using `GATEWAY_AUTHENTICATION_FAILED`, `GATEWAY_ACCESS_DENIED`,
`GATEWAY_RATE_LIMITED`, `GATEWAY_REQUEST_REJECTED`, or
`API_GATEWAY_UNAVAILABLE`. Gateway response bodies are not reflected to the
browser.

## Browser acceptance run

With PostgreSQL, the scanner, Ballerina, Identity Server, API Manager, and
Next.js running:

1. Sign in as an identity with `securescan-user`.
2. Submit an authorized scan from `/scans/new`.
3. Confirm API Manager records the request and Ballerina records the same
   correlation and subject without recording the token.
4. Let `/scans/{id}` poll through `/backend` until the job is terminal.
5. Confirm the completed persisted result is displayed.
6. Open `/history` and confirm the same scan remains visible after a reload.
7. Repeat one request with a token missing `securescan:scan` and expect a safe
   `403`; exercise the throttling policy and expect a safe `429`.

Capture Gateway, Ballerina, browser, and database evidence with all tokens,
client secrets, cookies, and the backend shared secret redacted.

## Repository verification

The repository checkpoint covers the deterministic parts of Day 28:

```sh
cd frontend
npm test
npm run typecheck
npm run lint
npm run build
```

The tests prove Gateway URL selection, fail-closed configuration, unchanged
server-side bearer forwarding, header isolation, and Gateway error
normalization. The API project YAML parses and the mediation XML remains
well-formed.

This development host does not provide Docker or API Controller, so the live
Identity Server key-manager registration, subscription, browser scan, scope
rejection, and throttling evidence remain external checks. Keep Issue #12 open
and off `Done` until every Browser acceptance step above has captured evidence.
