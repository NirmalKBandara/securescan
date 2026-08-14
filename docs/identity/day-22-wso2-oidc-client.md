# Day 22 — WSO2 OIDC client foundation

Day 22 defines the confidential OpenID Connect client that connects the
SecureScan Next.js server to WSO2 Identity Server. It fixes the issuer,
redirect, logout, scope, and role contracts before browser login is enabled.

## Register the development application

Start the identity server and sign in to `https://localhost:9443/console`.
Create a **Traditional Web Application** named `SecureScan Development` with
OpenID Connect, then configure:

- authorized redirect URL: `http://localhost:3000/auth/callback`
- authorized post-logout URL: `http://localhost:3000/login`
- allowed origin: `http://localhost:3000`
- grant type: Authorization Code only
- PKCE: required, using the S256 challenge method
- client authentication: client secret
- requested scopes: `openid profile email`

Use exact URLs. Do not register wildcard callbacks or add the implicit,
password, or client-credentials grants to this browser-facing application.
Copy the generated client ID and client secret to `frontend/.env.local`; never
put them in a `NEXT_PUBLIC_*` variable or commit that file.

The default WSO2 issuer is `https://localhost:9443/oauth2/token`, not the
Console origin. Its discovery document is therefore:

```text
https://localhost:9443/oauth2/token/.well-known/openid-configuration
```

## Establish the role contract

Create the application roles `securescan-user` and `securescan-admin` in WSO2.
Assign ordinary operators only to `securescan-user`; administrators may hold
both. Enable the WSO2 roles/groups claim for the application so it can be
requested during login. Day 24 maps and enforces these exact, case-sensitive
values; Day 22 does not yet authorize a route.

Development users and their passwords are operator-managed identity data in
the Day 21 volume. No bootstrap administrator password, user password, client
secret, token, or generated application ID belongs in Git.

## Frontend configuration contract

Copy `frontend/.env.example` to `.env.local` and replace the client credential
placeholders. `APP_BASE_URL` is the public browser origin used to derive exact
callback URLs. `OIDC_ISSUER` is validated as an absolute HTTP(S) issuer, while
the client ID and secret remain server-only.

The login button remains on its Day 20 placeholder during this checkpoint.
Day 23 uses this configuration to add Authorization Code with PKCE, validated
callbacks, server-managed sessions, and logout.

## Verification

With WSO2 running, inspect the provider metadata:

```sh
curl --fail --silent --show-error --insecure \
  https://localhost:9443/oauth2/token/.well-known/openid-configuration
```

The document must report the same issuer plus HTTPS authorization, token,
JWKS, and end-session endpoints. `--insecure` is acceptable only for the
bundled local development certificate.

Verify the repository contract independently of a running identity server:

```sh
cd frontend
npm test -- --run lib/auth/config.test.ts
npm run typecheck
npm run lint
```

The tests cover missing credentials, unsafe URL schemes, ambiguous base paths,
issuer normalization, and exact callback derivation.

## Security boundary

Application registration does not authenticate the current frontend or its
API requests. The Ballerina listener remains a pre-auth development endpoint,
and `authorized: true` remains an explicit permission acknowledgement. Token
validation and owner propagation require the later API Manager and Ballerina
integration checkpoints.
