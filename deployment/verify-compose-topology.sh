#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compose_file="${repository_root}/deployment/compose.yaml"
environment_file="${repository_root}/deployment/.env"

if [[ ! -f "${environment_file}" ]]; then
  echo "Missing deployment/.env; copy deployment/.env.example and configure it first." >&2
  exit 1
fi

compose=(docker compose --env-file "${environment_file}" --file "${compose_file}")

"${compose[@]}" config --quiet
"${compose[@]}" build --pull
"${compose[@]}" up --detach --wait
"${compose[@]}" ps

frontend_address="$("${compose[@]}" port frontend 3000)"
identity_address="$("${compose[@]}" port identity-server 9443)"
manager_address="$("${compose[@]}" port api-manager 9443)"
curl --fail --silent --show-error \
  "http://${frontend_address}/api/health" >/dev/null
curl --fail --silent --show-error --insecure \
  "https://${identity_address}/api/health-check/v1.0/health" >/dev/null
curl --fail --silent --show-error --insecure \
  "https://${manager_address}/publisher" >/dev/null

for private_service_port in \
  "postgres 5432" \
  "scanner-engine 8081" \
  "ballerina-api 9090"; do
  read -r service port <<<"${private_service_port}"
  if [[ -n "$("${compose[@]}" port "${service}" "${port}")" ]]; then
    echo "${service}:${port} must not be published to the host" >&2
    exit 1
  fi
done

assert_resolves() {
  local network="$1"
  local hostname="$2"
  docker run --rm --network "${network}" alpine:3.22 \
    getent hosts "${hostname}" >/dev/null
}

assert_not_resolves() {
  local network="$1"
  local hostname="$2"
  if docker run --rm --network "${network}" alpine:3.22 \
      getent hosts "${hostname}" >/dev/null 2>&1; then
    echo "${hostname} unexpectedly resolves on ${network}" >&2
    exit 1
  fi
}

assert_resolves securescan-data postgres
assert_resolves securescan-data ballerina-api
assert_not_resolves securescan-data frontend
assert_not_resolves securescan-data scanner-engine

assert_resolves securescan-scanner scanner-engine
assert_resolves securescan-scanner ballerina-api
assert_not_resolves securescan-scanner frontend
assert_not_resolves securescan-scanner postgres

assert_resolves securescan-integration ballerina-api
assert_resolves securescan-integration api-manager
assert_not_resolves securescan-integration frontend
assert_not_resolves securescan-integration postgres

assert_resolves securescan-gateway frontend
assert_resolves securescan-gateway api-manager
assert_not_resolves securescan-gateway postgres
assert_not_resolves securescan-gateway scanner-engine

assert_resolves securescan-identity frontend
assert_resolves securescan-identity identity-server
assert_resolves securescan-identity api-manager
assert_not_resolves securescan-identity postgres
assert_not_resolves securescan-identity scanner-engine

echo "SecureScan Compose health, port exposure, and DNS isolation checks passed."
