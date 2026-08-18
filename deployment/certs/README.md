# Local WSO2 trust material

Place the local development CA bundle at
`wso2-local-ca-bundle.pem` (or update `WSO2_CA_BUNDLE_HOST_PATH`). The bundle
must issue the Identity Server and API Manager certificates, including SANs
for their Compose service names. It is mounted read-only into the frontend.

Real certificates and keys in this directory are ignored. Never commit a
private key or disable Node TLS verification to work around a trust error.
