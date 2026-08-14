#!/usr/bin/env bash
set -euo pipefail

admin_url="${WSO2_APIM_ADMIN_URL:-https://localhost:9444}"
admin_token="${WSO2_APIM_ADMIN_TOKEN:-}"
if [[ -z "${admin_token}" ]]; then
  echo "WSO2_APIM_ADMIN_TOKEN is required" >&2
  exit 1
fi

curl_tls=()
if [[ "${WSO2_APIM_INSECURE:-false}" == "true" ]]; then
  curl_tls+=(--insecure)
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
policy_url="${admin_url%/}/api/am/admin/v4/throttling/policies/subscription"
existing="$(curl --fail --silent --show-error "${curl_tls[@]}" \
  --header "Authorization: Bearer ${admin_token}" \
  --header "Accept: application/json" "${policy_url}")"

for policy_file in \
  "${script_dir}/throttling/securescan-user.json" \
  "${script_dir}/throttling/securescan-admin.json"; do
  policy_name="$(jq -er '.policyName' "${policy_file}")"
  if jq -e --arg name "${policy_name}" \
      '.list[]? | select(.policyName == $name)' <<<"${existing}" >/dev/null; then
    echo "${policy_name}: already exists"
    continue
  fi
  curl --fail --silent --show-error "${curl_tls[@]}" \
    --request POST \
    --header "Authorization: Bearer ${admin_token}" \
    --header "Accept: application/json" \
    --header "Content-Type: application/json" \
    --data-binary "@${policy_file}" "${policy_url}" >/dev/null
  echo "${policy_name}: created"
done
