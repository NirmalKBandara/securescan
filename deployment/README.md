# Local platform services

The development Compose project runs the PostgreSQL system of record, WSO2
Identity Server 7.3.0, and WSO2 API Manager 4.7.0. All published ports bind to
`127.0.0.1`; they are not reachable from other machines unless the operator
deliberately changes that boundary.

## Start the services

From the repository root:

```sh
cp deployment/.env.example deployment/.env
docker compose --env-file deployment/.env -f deployment/compose.yaml up -d --wait
docker compose --env-file deployment/.env -f deployment/compose.yaml ps
```

The WSO2 services can take several minutes to become ready on first start.
Compose waits
for `https://localhost:9443/api/health-check/v1.0/health` before reporting the
service healthy. Inspect startup progress with:

```sh
docker compose -f deployment/compose.yaml logs -f identity-server
docker compose -f deployment/compose.yaml logs -f api-manager
```

Once healthy, open `https://localhost:9443/console`. The official development
image uses a self-signed certificate, so browsers and command-line clients will
report an untrusted certificate until a local trust setup is provided.

For a fresh upstream image, the development bootstrap sign-in is `admin` /
`admin`. It is for local setup only. Change the password immediately before
creating development users or applications. Never use bootstrap credentials,
the bundled certificate, or the embedded database in a deployed environment.

API Manager uses separate host ports:

- Publisher: `https://localhost:9444/publisher`
- Developer Portal: `https://localhost:9444/devportal`
- HTTPS Gateway: `https://localhost:8243`

The API Manager container maps `host.docker.internal` to the development host
so a Day 27 endpoint can reach Ballerina at
`http://host.docker.internal:9090`. See the
[Day 26 API Manager foundation](../docs/gateway/day-26-wso2-api-manager.md)
for the full component and authentication plan.

The importable API project and Gateway acceptance procedure are documented in
the [Day 27 publishing runbook](../docs/gateway/day-27-api-manager-publishing.md).
The imported API also restricts CORS to `http://localhost:3000` and binds every
operation to `securescan:scan`. The frontend application, out-of-band client,
subscription, scope, identity, and browser verification are covered by the
[Day 28 Gateway routing runbook](../docs/gateway/day-28-gateway-routing.md).
Install the Day 29 user/admin subscription policies with
`apim/configure-throttling.sh`, then follow the authorized live checks in the
[Day 29 throttling runbook](../docs/gateway/day-29-api-throttling.md).
Re-import the API project for the Day 30 `securescan:admin` scope and
allowed-target operations, then follow the
[Day 30 administration runbook](../docs/security/day-30-allowed-target-administration.md).
Re-import again after Day 32 to expose the admin scan, audit-log, and usage
resources used by the dashboard; their role and UI checks are documented in the
[Day 32 dashboard runbook](../docs/frontend/day-32-administrator-dashboard.md).

Override a host port without editing the Compose file:

```sh
WSO2_IS_HTTPS_PORT=9444 docker compose -f deployment/compose.yaml up -d --wait
```

Only the TLS listener is published. WSO2's plain HTTP listener and internal
management ports remain inside the Compose network.

## Persistence and shutdown

Identity data is retained in the named volume
`securescan-identity-server-development-data`. PostgreSQL uses its existing
`securescan-postgres-development-data` volume, and API Manager uses
`securescan-api-manager-development-data`. A normal shutdown retains all three:

```sh
docker compose -f deployment/compose.yaml down
```

Removing volumes deletes all local database and identity data. Only do this
when a full development reset is intended:

```sh
docker compose -f deployment/compose.yaml down --volumes
```

Days 21–25 establish identity, sessions, route protection, scan ownership, and
API-side roles. Day 26 adds the API management runtime; Day 27 imports and
publishes the versioned API through its Gateway.
