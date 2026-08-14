# Day 26: WSO2 API Manager foundation

SecureScan pins the local API management runtime to WSO2 API Manager 4.7.0.
The single-node development container provides the Publisher, Developer Portal,
Gateway, application/subscription management, lifecycle controls, and
throttling needed for Day 27.

## Local topology

| Capability | Local URL | Purpose |
| --- | --- | --- |
| Publisher | `https://localhost:9444/publisher` | Import, configure, deploy, and publish API v1 |
| Developer Portal | `https://localhost:9444/devportal` | Discover the API; create applications and subscriptions |
| Admin Portal | `https://localhost:9444/admin` | Gateway, policy, and tenant administration |
| Carbon console | `https://localhost:9444/carbon` | Development runtime administration |
| OAuth token endpoint | `https://localhost:9444/oauth2/token` | Obtain a test-application access token |
| HTTPS Gateway | `https://localhost:8243` | Invoke published APIs |
| Ballerina backend | `http://host.docker.internal:9090` | Container-to-host development endpoint |

WSO2 Identity Server retains host port `9443`; API Manager uses `9444` to avoid
a collision. Management and Gateway ports bind to `127.0.0.1`. The Compose
`host-gateway` mapping lets API Manager reach a Ballerina listener running on
the development host without publishing that listener through Compose.

## Start and inspect

Requirements are Docker Engine with Compose v2, enough memory for two WSO2 JVMs
plus the application services, and free loopback ports `5432`, `8243`, `9443`,
and `9444`.

```sh
cp deployment/.env.example deployment/.env
docker compose --env-file deployment/.env \
  -f deployment/compose.yaml up -d --wait
docker compose --env-file deployment/.env \
  -f deployment/compose.yaml ps
```

First startup downloads the pinned image and may take several minutes. Follow
only the API Manager logs with:

```sh
docker compose --env-file deployment/.env \
  -f deployment/compose.yaml logs -f api-manager
```

The development image uses a self-signed certificate. After Compose reports the
service healthy, verify the two portals and Gateway TLS listener:

```sh
curl --fail --insecure --head https://localhost:9444/publisher
curl --fail --insecure --head https://localhost:9444/devportal
curl --insecure --include https://localhost:8243/
```

The Publisher and Developer Portal must return an HTTP response. A Gateway
`404` at the root is expected before an API is deployed and proves the listener
is reachable. The upstream image's `admin` / `admin` bootstrap account is for
disposable local development only and must be changed before retaining data.

## Component inspection record

- Publisher owns API definition, endpoint, revision, deployment, lifecycle, and
  subscription-tier configuration.
- Developer Portal owns application registration, API subscription, credential
  generation, discovery, and invocation documentation.
- Gateway exposes the versioned context and rejects missing/invalid OAuth2
  credentials before routing.
- Applications group credentials and subscriptions for a caller.
- Subscriptions bind an application to SecureScan v1 and a business plan.
- Lifecycle moves the imported API from `CREATED` to `PUBLISHED`; deployment of
  a revision is separate from publication.
- Throttling is applied at the Gateway and supplements, but does not replace,
  Ballerina's per-owner active-scan limit.

## Authentication and backend decision

The Gateway is the only supported external entry point. It validates the OAuth2
access token and then replaces all inbound `X-SecureScan-*` headers with trusted
values derived from validated claims. The backend request contains the subject,
exact SecureScan roles, and a server-only shared secret. Ballerina verifies that
secret, repeats role authorization, and applies the persisted owner predicate.

The Day 27 test application uses API Manager-issued credentials. The Next.js
frontend remains in `direct` mode until API Manager is configured to accept the
WSO2 Identity Server issuer as a key manager; only then should it switch to
`gateway` mode and forward the user's access token. This avoids treating an ID
token as an API credential or falsely assuming tokens from two issuers are
interchangeable.

## Verification state

The Compose YAML parses successfully and pins a real multi-architecture WSO2
4.7.0 image. Live startup and portal checks must run on a Docker-capable host.
Do not mark Issue #10 complete or move it to `Done` until the `--wait`, portal,
and Gateway checks above are captured. This repository intentionally records
that external-runtime check as pending rather than fabricating evidence.
