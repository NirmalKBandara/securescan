# Day 21 — WSO2 Identity Server foundation

Day 21 adds the local identity-provider runtime that later authentication and
authorization checkpoints will build on. It deliberately establishes the
service boundary without prematurely putting tokens or browser sessions into
the SecureScan request path.

## Delivered behavior

- The Compose project runs the official `wso2/wso2is:7.3.0` image rather than a
  moving `latest` tag.
- WSO2 HTTPS is published on `127.0.0.1:9443` by default. The port can be
  overridden with `WSO2_IS_HTTPS_PORT` without widening the bind address.
- The plain HTTP transport, LDAP, JMX, and other internal ports are not
  published to the host.
- Compose checks the built-in Carbon health resource and allows for the longer
  JVM/OSGi startup period before judging the service unhealthy.
- Embedded development identity data survives an ordinary container
  recreation in the named `securescan-identity-server-development-data`
  volume.
- Start, health, log, shutdown, reset, and TLS guidance lives beside the
  Compose definition in `deployment/README.md`.

The embedded data store and bundled self-signed certificate make this a local
development topology, not a production deployment pattern.

## Local verification

From the repository root:

```sh
docker compose -f deployment/compose.yaml config --quiet
docker compose -f deployment/compose.yaml up -d --wait identity-server
docker compose -f deployment/compose.yaml ps identity-server
curl --fail --silent --show-error --insecure \
  https://localhost:9443/api/health-check/v1.0/health
```

The service should be reported as healthy and the health request should return
HTTP 200. The administrator console is available at
`https://localhost:9443/console`. A fresh upstream image uses the public
development bootstrap credentials `admin` / `admin`; change the password
before adding development identities or applications.

Verify the local-only host boundary with:

```sh
docker compose -f deployment/compose.yaml port identity-server 9443
```

The reported address must begin with `127.0.0.1:`. After creating disposable
development identity data, run `docker compose ... down` followed by another
`up -d --wait` and confirm that the data remains. Do not use `--volumes` for
that persistence check.

The implementation environment used for this checkpoint did not provide a
Docker daemon or Docker CLI. The Compose document therefore received static
YAML and repository checks here; the commands above remain the required local
runtime acceptance test on a Docker-capable host.

## Security boundary

The official image's bootstrap administrator, embedded database, and bundled
certificate are development conveniences. Change the bootstrap password before
creating users or applications, do not expose port 9443 beyond loopback, and do
not commit administrator passwords, client secrets, tokens, or replacement
private keys.

The Carbon health resource is exposed only through the same loopback-bound TLS
listener in this topology. A later production deployment must use managed
secrets and certificates, an external supported database, restricted
administration paths, network policy, backups, and a reviewed upgrade process.

## Deferred integration

This checkpoint does not register SecureScan as an OIDC application and does
not change the frontend login placeholder. Authorization Code with PKCE,
server-managed sessions, logout, protected routes, immutable `iss + sub`
ownership, role mapping, API Manager policy, and Ballerina token enforcement
remain later milestones. Until those are complete, `authorized: true` is still
an explicit scan-permission acknowledgement and is not proof of identity.
