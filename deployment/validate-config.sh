#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
environment_file="${1:-${repository_root}/deployment/.env}"

if [[ ! -f "${environment_file}" ]]; then
  echo "Missing ${environment_file}; copy deployment/.env.example and configure it first." >&2
  exit 1
fi

declare -A values=()
while IFS='=' read -r raw_name raw_value; do
  name="${raw_name//[[:space:]]/}"
  [[ -z "${name}" || "${name}" == \#* ]] && continue
  if [[ ! "${name}" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
    echo "Invalid variable name in ${environment_file}: ${raw_name}" >&2
    exit 1
  fi
  values["${name}"]="${raw_value%$'\r'}"
done <"${environment_file}"

required=(
  POSTGRES_DB POSTGRES_USER POSTGRES_PASSWORD
  SECURESCAN_GATEWAY_SHARED_SECRET
  OIDC_CLIENT_ID OIDC_CLIENT_SECRET AUTH_SESSION_SECRET
  COMPOSE_OIDC_ISSUER
)

for name in "${required[@]}"; do
  value="${values[${name}]:-}"
  if [[ -z "${value}" ]]; then
    echo "${name} is required in ${environment_file}." >&2
    exit 1
  fi
  if [[ "${value,,}" == replace-with* || "${value,,}" == change-me* || "${value,,}" == changeme* ]]; then
    echo "${name} still contains an example placeholder; set a real local value." >&2
    exit 1
  fi
done

for name in POSTGRES_PASSWORD SECURESCAN_GATEWAY_SHARED_SECRET OIDC_CLIENT_SECRET AUTH_SESSION_SECRET; do
  if (( ${#values[${name}]} < 32 )); then
    echo "${name} must contain at least 32 characters." >&2
    exit 1
  fi
done

if [[ ! "${values[COMPOSE_OIDC_ISSUER]}" =~ ^https://[^[:space:]]+$ ]]; then
  echo "COMPOSE_OIDC_ISSUER must be an absolute HTTPS URL." >&2
  exit 1
fi

numeric=(
  MAX_PORTS_PER_SCAN MAX_CONCURRENT_PORTS MAX_ACTIVE_SCANS MAX_RETAINED_JOBS
  SCAN_TIMEOUT_MS API_MAX_REQUEST_BYTES API_GATEWAY_TIMEOUT_MS
  DISPATCH_LEASE_SECONDS RECONCILIATION_INTERVAL_SECONDS
)
for name in "${numeric[@]}"; do
  value="${values[${name}]:-}"
  if [[ ! "${value}" =~ ^[1-9][0-9]*$ ]]; then
    echo "${name} must be a positive integer." >&2
    exit 1
  fi
done

for name in WSO2_IS_HTTPS_PORT WSO2_APIM_HTTPS_PORT \
  WSO2_APIM_GATEWAY_HTTPS_PORT FRONTEND_PORT; do
  value="${values[${name}]:-}"
  if [[ ! "${value}" =~ ^[1-9][0-9]*$ ]] || (( value > 65535 )); then
    echo "${name} must be a TCP port between 1 and 65535." >&2
    exit 1
  fi
done

declare -A used_ports=()
for name in WSO2_IS_HTTPS_PORT WSO2_APIM_HTTPS_PORT \
  WSO2_APIM_GATEWAY_HTTPS_PORT FRONTEND_PORT; do
  value="${values[${name}]}"
  if [[ -n "${used_ports[${value}]:-}" ]]; then
    echo "${name} conflicts with ${used_ports[${value}]} on host port ${value}." >&2
    exit 1
  fi
  used_ports["${value}"]="${name}"
done

if (( values[MAX_PORTS_PER_SCAN] > 1000 )); then
  echo "MAX_PORTS_PER_SCAN cannot exceed the hard limit 1000." >&2
  exit 1
fi
if (( values[API_MAX_REQUEST_BYTES] > 4096 )); then
  echo "API_MAX_REQUEST_BYTES cannot exceed the hard limit 4096." >&2
  exit 1
fi
if (( values[API_GATEWAY_TIMEOUT_MS] > 10000 )); then
  echo "API_GATEWAY_TIMEOUT_MS cannot exceed the hard limit 10000." >&2
  exit 1
fi

for name in SCANNER_CONNECT_TIMEOUT_SECONDS SCANNER_RESPONSE_TIMEOUT_SECONDS; do
  value="${values[${name}]:-}"
  if [[ ! "${value}" =~ ^([0-9]+([.][0-9]+)?|[.][0-9]+)$ || \
      "${value}" =~ ^0+([.]0+)?$ ]]; then
    echo "${name} must be a positive decimal number." >&2
    exit 1
  fi
done

if [[ " ${values[OIDC_SCOPES]:-} " != *" openid "* || \
      " ${values[OIDC_SCOPES]:-} " != *" securescan:scan "* ]]; then
  echo "OIDC_SCOPES must include openid and securescan:scan." >&2
  exit 1
fi
if [[ -z "${values[OIDC_ROLE_CLAIM]:-}" ]]; then
  echo "OIDC_ROLE_CLAIM is required." >&2
  exit 1
fi

image_version="${values[WSO2_APIM_IMAGE]##*:}"
if [[ "${image_version}" != "${values[WSO2_APIM_HOME_VERSION]:-}" ]]; then
  echo "WSO2_APIM_HOME_VERSION must match the WSO2_APIM_IMAGE tag." >&2
  exit 1
fi

for name in POSTGRES_VOLUME_NAME IDENTITY_VOLUME_NAME APIM_VOLUME_NAME \
  IDENTITY_NETWORK_NAME GATEWAY_NETWORK_NAME INTEGRATION_NETWORK_NAME \
  SCANNER_NETWORK_NAME DATA_NETWORK_NAME; do
  value="${values[${name}]:-}"
  if [[ ! "${value}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]+$ ]]; then
    echo "${name} must be a non-empty Docker resource name." >&2
    exit 1
  fi
done

echo "SecureScan deployment configuration is complete and contains no example credentials."
