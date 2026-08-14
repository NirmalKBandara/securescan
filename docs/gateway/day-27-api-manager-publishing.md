# Day 27: publish SecureScan API v1

Day 27 provides an importable API Controller project at
`deployment/apim/securescan-api`. It contains the OpenAPI 3.0.3 contract, the
`/securescan/v1` Gateway context, the Ballerina production endpoint, and an
inbound identity mediation sequence.

## Security flow

```text
test application access token
  -> API Manager OAuth2 and subscription validation
  -> API Manager throttling
  -> remove caller-supplied X-SecureScan-* headers
  -> add validated subject, roles, and backend shared secret
  -> Ballerina role and persisted-owner authorization
```

The sequence reads API Manager's authenticated `api.ut.userId` and
`api.ut.userRoles` properties only after the authentication handler has accepted
the token. The shared secret is substituted from
`SECURESCAN_GATEWAY_SHARED_SECRET` during import. Never place a deployed secret
in `api.yaml`, OpenAPI, XML, screenshots, shell history, or Git.

## Prerequisites

1. Complete the Day 26 startup checks.
2. Run PostgreSQL, the Go scanner, and Ballerina. Ballerina must use
   `authenticationEnabled=true` and the same shared secret.
3. Install API Controller compatible with API Manager 4.7.0.
4. In API Manager's Carbon console, create the exact roles
   `securescan-user` and `securescan-admin`. Give the test application owner
   `securescan-user`; reserve `securescan-admin` for an administrator test
   identity.

## Import and publish

Register and authenticate the local environment. Let `apictl` prompt for the
development credentials so they are not included in commands:

```sh
apictl add env securescan-local --apim https://localhost:9444
apictl login securescan-local --insecure
```

Export the ignored local environment values, then import the project. API
Controller replaces the secret placeholder in the custom mediation policy:

```sh
set -a
. deployment/.env
set +a
apictl import api -f deployment/apim/securescan-api \
  --environment securescan-local --insecure
```

In Publisher, open `SecureScanAPI : v1` and verify:

- context is `/securescan/v1`;
- production endpoint is `http://host.docker.internal:9090`;
- HTTPS is the only transport;
- the `securescan-identity-in` request policy is attached;
- `Unlimited` is available for the development subscription;
- all three OpenAPI operations are visible.

Create and deploy a revision to the `Default` Gateway if the import did not
deploy one. Confirm the lifecycle is `PUBLISHED` and that the API appears in the
Developer Portal. Publication and Gateway deployment are separate WSO2 states;
both are required.

## Test application and subscription

In Developer Portal:

1. Create `SecureScanTest` with the test user that has `securescan-user`.
2. Open SecureScan API v1 and subscribe `SecureScanTest` with `Unlimited`.
3. Generate production OAuth2 keys and a short-lived access token.
4. Store the token only in the current shell as
   `SECURESCAN_GATEWAY_TOKEN`.

Run the acceptance script:

```sh
SECURESCAN_GATEWAY_TOKEN='<short-lived-token>' \
  deployment/apim/verify-gateway.sh
```

The script requires these results:

| Request | Expected result |
| --- | --- |
| No token | Gateway `401` or `403`; Ballerina is not called |
| Invalid bearer token | Gateway `401` or `403`; Ballerina is not called |
| Valid subscribed token | `200` history response from Ballerina |

Use API Manager access logs and Ballerina logs to capture the ordering: the two
rejected requests appear only at the Gateway, while the valid request has a
Ballerina correlation ID. Do not capture access tokens or the shared secret.

For an additional owner check, create a scan through the Gateway as User A,
then request its ID as User B and expect `404`. Give a separate identity the
exact `securescan-admin` role and confirm it can select User A's history through
`ownerSubject`.

## Frontend cutover

Only after API Manager accepts access tokens from the WSO2 Identity Server key
manager should the frontend change to:

```text
SECURESCAN_API_MODE=gateway
BALLERINA_API_BASE_URL=https://localhost:8243/securescan/v1
```

Trust the local Gateway certificate with `NODE_EXTRA_CA_CERTS`; never disable
Node TLS verification globally. The browser continues to call `/backend`, and
only the server route handler sees the access token.

## Verification state

The OpenAPI document parses, all local references resolve, the API project YAML
parses, the mediation sequence is well-formed XML, and the acceptance script
passes shell syntax validation. This host has no Docker runtime or `apictl`, so
the import, application/subscription creation, live publication, and Gateway
calls remain external checks. Keep Issues #10 and #11 open and off `Done` until
their captured live evidence satisfies the tables above.
