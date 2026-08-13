# Local platform services

The development Compose project runs the PostgreSQL system of record and WSO2
Identity Server 7.3.0. Both services bind host ports to `127.0.0.1`; they are not
reachable from other machines unless the operator deliberately changes that
boundary.

## Start the services

From the repository root:

```sh
docker compose -f deployment/compose.yaml up -d --wait
docker compose -f deployment/compose.yaml ps
```

WSO2 can take several minutes to become ready on its first start. Compose waits
for `https://localhost:9443/api/health-check/v1.0/health` before reporting the
service healthy. Inspect startup progress with:

```sh
docker compose -f deployment/compose.yaml logs -f identity-server
```

Once healthy, open `https://localhost:9443/console`. The official development
image uses a self-signed certificate, so browsers and command-line clients will
report an untrusted certificate until a local trust setup is provided.

The upstream image's bootstrap administrator is for local setup only. Change
the password immediately before creating development users or applications.
Never use bootstrap credentials, the bundled certificate, or the embedded
database in a deployed environment.

Override a host port without editing the Compose file:

```sh
WSO2_IS_HTTPS_PORT=9444 docker compose -f deployment/compose.yaml up -d --wait
```

Only the TLS listener is published. WSO2's plain HTTP listener and internal
management ports remain inside the Compose network.

## Persistence and shutdown

Identity data is retained in the named volume
`securescan-identity-server-development-data`. PostgreSQL uses its existing
`securescan-postgres-development-data` volume. A normal shutdown retains both:

```sh
docker compose -f deployment/compose.yaml down
```

Removing volumes deletes all local database and identity data. Only do this
when a full development reset is intended:

```sh
docker compose -f deployment/compose.yaml down --volumes
```

Day 21 establishes the identity provider runtime only. SecureScan OIDC
application registration, frontend sessions, route protection, roles, and API
token enforcement are later checkpoints.
