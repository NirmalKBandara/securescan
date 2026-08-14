#!/usr/bin/env bash
set -euo pipefail

gateway_url="${SECURESCAN_GATEWAY_URL:-https://localhost:8243/securescan/v1}"
backend_url="${SECURESCAN_BALLERINA_URL:-http://localhost:9090}"
access_token="${SECURESCAN_GATEWAY_TOKEN:-}"
target="${SECURESCAN_TEST_TARGET:-}"

if [[ -z "${access_token}" || -z "${target}" ]]; then
  echo "SECURESCAN_GATEWAY_TOKEN and SECURESCAN_TEST_TARGET are required" >&2
  exit 1
fi

for command_name in curl jq; do
  if ! command -v "${command_name}" >/dev/null; then
    echo "${command_name} is required" >&2
    exit 1
  fi
done

curl_tls=()
if [[ "${SECURESCAN_CURL_INSECURE:-false}" == "true" ]]; then
  curl_tls+=(--insecure)
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  find "${tmp_dir}" -type f -delete
  rmdir "${tmp_dir}"
}
trap cleanup EXIT

request() {
  local output_file="$1"
  shift
  curl --silent --show-error "${curl_tls[@]}" \
    --output "${output_file}" --write-out '%{http_code}' "$@"
}

assert_status() {
  local actual="$1"
  local expected="$2"
  local description="$3"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "${description}: expected HTTP ${expected}, received ${actual}" >&2
    exit 1
  fi
  echo "${description}: HTTP ${actual}"
}

auth_headers=(
  --header "Authorization: Bearer ${access_token}"
  --header 'Accept: application/json'
)

status="$(request "${tmp_dir}/allowed.json" "${auth_headers[@]}" \
  "${gateway_url%/}/api/v1/scans?page=1&pageSize=1")"
assert_status "${status}" 200 "allowed Gateway request"

too_many_ports="$(jq -nc --arg target "${target}" \
  '{target: $target, startPort: 1, endPort: 1001, authorized: true}')"
status="$(request "${tmp_dir}/ports.json" "${auth_headers[@]}" \
  --header 'Content-Type: application/json' --request POST \
  --data-binary "${too_many_ports}" "${gateway_url%/}/api/v1/scans")"
assert_status "${status}" 400 "1,001-port application limit"
jq -e '.error.code == "INVALID_PORT_RANGE"' "${tmp_dir}/ports.json" >/dev/null

printf -v padding '%*s' 4097 ''
padding="${padding// /x}"
oversized="$(jq -nc --arg padding "${padding}" '{padding: $padding}')"
status="$(request "${tmp_dir}/oversized.json" "${auth_headers[@]}" \
  --header 'Content-Type: application/json' --request POST \
  --data-binary "${oversized}" "${gateway_url%/}/api/v1/scans")"
assert_status "${status}" 413 "request-size limit"

active_scan="$(jq -nc --arg target "${target}" \
  '{target: $target, startPort: 1, endPort: 1000, authorized: true}')"
status="$(request "${tmp_dir}/first-scan.json" "${auth_headers[@]}" \
  --header 'Content-Type: application/json' --request POST \
  --data-binary "${active_scan}" "${gateway_url%/}/api/v1/scans")"
assert_status "${status}" 202 "first active scan"
status="$(request "${tmp_dir}/second-scan.json" "${auth_headers[@]}" \
  --header 'Content-Type: application/json' --request POST \
  --data-binary "${active_scan}" "${gateway_url%/}/api/v1/scans")"
assert_status "${status}" 429 "one-active-scan limit"
jq -e '.error.code == "JOB_LIMIT_REACHED"' "${tmp_dir}/second-scan.json" >/dev/null

throttled=false
for attempt in $(seq 1 80); do
  status="$(request "${tmp_dir}/throttle-${attempt}.json" "${auth_headers[@]}" \
    "${gateway_url%/}/api/v1/scans?page=1&pageSize=1")"
  if [[ "${status}" == "429" ]]; then
    throttled=true
    echo "Gateway quota: HTTP 429 after ${attempt} rapid requests"
    break
  fi
done
if [[ "${throttled}" != "true" ]]; then
  echo "Gateway did not throttle within 80 rapid requests" >&2
  exit 1
fi

status="$(request "${tmp_dir}/direct.json" \
  "${backend_url%/}/api/v1/scans?page=1&pageSize=1")"
assert_status "${status}" 401 "direct-backend bypass protection"

echo "Day 29 security-limit acceptance checks passed. Preserve redacted outputs as evidence."
