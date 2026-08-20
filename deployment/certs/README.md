# Local WSO2 trust material

Place the local development CA bundle at
`wso2-local-ca-bundle.pem` (or update `WSO2_CA_BUNDLE_HOST_PATH`). It is mounted
read-only into the frontend so Next.js can validate the WSO2 services.

The bundle is only the trust anchor; it does not replace either WSO2 product's
server certificate. The configured certificates must be issued by that CA and
must cover every name used by a client:

- Identity Server: `localhost` for browser use and `identity-server` for the
  frontend's Compose issuer URL.
- API Manager: `localhost` for browser/host tools and `api-manager` for the
  frontend's Compose Gateway URL.

This repository does not generate those certificates, mount WSO2 keystores, or
provide product-specific `deployment.toml` overrides. Provision the keystores,
public URLs, and service-name SANs using the selected WSO2 development setup
before starting the frontend. Until that operator-owned configuration exists,
the full browser-to-Gateway Compose flow is not reproducible from the CA bundle
alone and the Day 37 live gate remains pending.

Real certificates and keys in this directory are ignored. Never commit a
private key, accept a hostname mismatch, or disable Node TLS verification to
work around a trust error.
