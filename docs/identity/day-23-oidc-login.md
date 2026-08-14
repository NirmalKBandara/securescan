# Day 23 — OIDC login and server-managed sessions

Day 23 connects the Next.js frontend to the Day 22 WSO2 application. Sign-in
now uses OpenID Connect Authorization Code with PKCE, and the browser receives
only encrypted, HttpOnly application cookies rather than provider tokens.

## Delivered flow

1. `GET /auth/login` discovers WSO2 metadata from the configured issuer.
2. The server generates a fresh state, nonce, and PKCE verifier/challenge.
3. An encrypted, ten-minute transaction cookie retains the verifier and a
   validated same-origin return path.
4. WSO2 authenticates the user and returns an authorization code to the exact
   `/auth/callback` URI.
5. The callback validates state, nonce, PKCE, issuer, audience, signature, and
   token time claims while exchanging the one-time code.
6. A successful callback rotates the transaction into an encrypted, HttpOnly,
   SameSite=Lax application session bounded by the ID token expiry and an
   eight-hour maximum.
7. `POST /auth/logout` clears all local authentication cookies and, when WSO2
   is available, redirects through its end-session endpoint with the validated
   ID token as a logout hint.

The login route refuses an identity provider that does not advertise PKCE
S256. Callback errors are deliberately generic in the browser and clear any
partial authentication state. Return destinations reject absolute URLs,
scheme-relative URLs, authentication endpoints, and oversized input.

## Configuration

Copy `frontend/.env.example` to `.env.local` and set:

- `APP_BASE_URL` to the browser-visible Next.js origin;
- `OIDC_ISSUER` to WSO2's `.../oauth2/token` issuer;
- `OIDC_CLIENT_ID` and `OIDC_CLIENT_SECRET` from the Day 22 application;
- `AUTH_SESSION_SECRET` to at least 32 random characters.

Generate the session secret with `openssl rand -base64 32`. Never prefix the
client secret or session secret with `NEXT_PUBLIC_`; both are server-only.
Rotating `AUTH_SESSION_SECRET` intentionally invalidates outstanding login
transactions and sessions.

The bundled WSO2 certificate is self-signed. Prefer exporting that development
CA/certificate and starting Next.js with `NODE_EXTRA_CA_CERTS` pointing to the
PEM file. Do not disable TLS verification globally. Deployed environments must
use a trusted certificate and HTTPS `APP_BASE_URL`, which also enables the
Secure flag on authentication cookies.

## Verification

Run the reproducible frontend suite:

```sh
cd frontend
npm ci
npm test
npm run typecheck
npm run lint
npm run build
```

The unit suite covers configuration rejection, safe redirects, authenticated
encryption, tampered/wrong-key cookies, live and expired sessions, and expired
OIDC transactions. `npm audit --omit=dev` must report no production dependency
vulnerabilities.

With WSO2 and Next.js running, confirm that `/auth/login` redirects to the
advertised authorization endpoint with `response_type=code`, a state, nonce,
and `code_challenge_method=S256`. Complete login, confirm the header shows the
validated display name, then sign out and confirm both the local and WSO2
sessions end. Access tokens, ID tokens, client secrets, and PKCE verifiers must
not appear in browser JavaScript storage or callback URLs after completion.

## Security boundary

Day 23 authenticates the frontend session but deliberately does not authorize
application routes; that is Day 24. It also does not make Ballerina a protected
resource server. The `/backend` rewrite still reaches the pre-auth Ballerina
development API, whose owner is not yet derived from the WSO2 subject. API
Manager policy and Ballerina token validation remain later checkpoints.
