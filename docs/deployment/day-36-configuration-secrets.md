# Day 36 — Configuration and secret handling

Day 36 moves local deployment values behind one validated configuration
boundary. The committed `deployment/.env.example` is an inventory of every
Compose substitution; it deliberately contains unusable credential
placeholders. Real values belong only in ignored `deployment/.env`.

## Prepare local configuration

```sh
cp deployment/.env.example deployment/.env
openssl rand -base64 36  # PostgreSQL password
openssl rand -base64 36  # Gateway-to-Ballerina shared secret
openssl rand -base64 36  # Next.js session secret
```

Replace `POSTGRES_PASSWORD`, `SECURESCAN_GATEWAY_SHARED_SECRET`, and
`AUTH_SESSION_SECRET` immediately. Leave the OIDC placeholders only during the
partial WSO2 bootstrap below; the frontend must not be started in that state.
Do not reuse any generated values. Validate the finished file only after the
real OIDC client values and CA bundle exist:

```sh
deployment/validate-config.sh deployment/.env
deployment/verify-secrets.sh
```

The validator rejects missing values, example placeholders, short secrets,
invalid or conflicting host ports, invalid limits/timeouts, incomplete OIDC
scopes, and API Manager image/home-version mismatches. Compose also uses
required-variable interpolation for credentials, and Next.js and Ballerina
reject missing or placeholder application secrets during startup.

## Initial WSO2 configuration

1. With the three generated secrets filled, start only the dependencies that do
   not consume the OIDC client placeholders:

   ```sh
   docker compose --env-file deployment/.env -f deployment/compose.yaml \
     up -d --build --wait postgres scanner-engine ballerina-api \
     identity-server api-manager
   ```

   Do not run the frontend or claim the environment passes preflight yet.
2. Open `https://localhost:9443/console`, replace the image's bootstrap
   password, create the `securescan-user` and `securescan-admin` roles, and
   create the test identities described in the Day 21–25 runbooks.
3. Register a Traditional Web Application with callback
   `http://localhost:3000/auth/callback`, logout URL
   `http://localhost:3000/login`, Authorization Code plus PKCE, and the exact
   ordinary `securescan:scan` scope in `OIDC_SCOPES`. Copy its client values
   into `deployment/.env`. Do not add `securescan:admin` to this ordinary
   application; the separate browser-admin client/grant flow is not yet
   implemented.
4. Import and publish `deployment/apim/securescan-api`, create the frontend
   application/subscription, install the Day 29 throttling policies, and use
   the same `SECURESCAN_GATEWAY_SHARED_SECRET` in the Gateway mediation policy.
5. Configure WSO2 certificates/public URLs so browser-facing endpoints use
   `localhost`, while service-to-service TLS names match their Compose service
   names. Put the issuing CA bundle at the host path configured by
   `WSO2_CA_BUNDLE_HOST_PATH`; Compose mounts it read-only and sets
   `NODE_EXTRA_CA_CERTS` inside the frontend. The repository does not generate
   or mount the required WSO2 keystores; the exact manual prerequisite and
   current limitation are recorded in the
   [certificate guide](../../deployment/certs/README.md). Never disable TLS
   verification or accept a hostname mismatch.
6. Replace every remaining placeholder, validate the environment, and only then
   start the full stack:

   ```sh
   deployment/validate-config.sh deployment/.env
   deployment/verify-secrets.sh
   docker compose --env-file deployment/.env -f deployment/compose.yaml \
     up -d --build --wait
   ```

WSO2's embedded databases and bundled certificate are development-only. Any
generated databases, keystores, PEM files, private keys, logs, and local
`deployment.toml` overrides under `deployment/wso2/` are ignored by Git.

## Database migration procedure

A fresh Compose volume receives V001–V006 in order through PostgreSQL's
initialization directory. Day 37 also records those versions in
`schema_migrations`, so later migration runs are idempotent. For an existing
healthy database:

```sh
set -a
. deployment/.env
set +a
database/scripts/migrate.sh up
database/scripts/verify.sh
```

Do not run `database/scripts/reset.sh` against a retained environment. It is a
development-only destructive reset and must be followed by a fresh migration
and seed.

## Acceptance evidence

The following repository checks pass on this workstation:

- `.env.example` is rejected because placeholders are intentionally unusable.
- A fully populated temporary environment passes preflight validation.
- tracked files and Git history pass the built-in credential signatures;
- all 86 frontend tests, ESLint, TypeScript, the production frontend build, and
  all Go tests pass;
- Ballerina compiles with Java 21; its socket-opening test suite cannot run in
  the current restricted workspace and is delegated to CI;
- shell syntax and `git diff --check` pass.

Live WSO2 and Compose evidence remains intentionally deferred to the
Docker-capable Day 37 gate.
