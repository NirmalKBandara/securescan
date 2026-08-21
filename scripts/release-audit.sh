#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
audit_target="${1:-all}"
evidence_root="${SECURESCAN_EVIDENCE_DIR:-${repository_root}/deployment/evidence/day-41}"

required_operations=(
  getHealth
  createScan
  listScans
  getScan
  listAdminScans
  listAuditLogs
  getAdminUsage
  listAllowedTargets
  createAllowedTarget
  disableAllowedTarget
)

required_evidence=(
  01-login.png
  02-apim-api.png
  03-apim-subscription.png
  04-scan-request.png
  05-scan-result.png
  06-history-after-restart.png
  07-admin-review.png
  08-throttled-response.png
  09-containers.png
  10-ci.png
  manifest.txt
)

check_source_release_files() {
  local openapi_file="${repository_root}/deployment/apim/securescan-api/Definitions/swagger.yaml"
  local operation

  [[ -s "${repository_root}/LICENSE" ]] || {
    echo "Missing LICENSE." >&2
    return 1
  }
  rg --quiet --fixed-strings '[MIT License](LICENSE)' "${repository_root}/README.md" || {
    echo "README does not link the project license." >&2
    return 1
  }

  for operation in "${required_operations[@]}"; do
    if [[ "$(rg --count --fixed-strings "operationId: ${operation}" "${openapi_file}")" != "1" ]]; then
      echo "OpenAPI must contain operationId ${operation} exactly once." >&2
      return 1
    fi
  done

  "${repository_root}/scripts/verify-clean-room.sh" all
}

check_runtime_evidence() {
  local artifact
  local missing=0
  local manifest="${evidence_root}/manifest.txt"

  for artifact in "${required_evidence[@]}"; do
    if [[ ! -s "${evidence_root}/${artifact}" ]]; then
      echo "Pending evidence: ${evidence_root}/${artifact}" >&2
      missing=1
    fi
  done

  if [[ -s "${manifest}" ]]; then
    rg --quiet '^VIDEO_URL=https://.+' "${manifest}" || {
      echo "manifest.txt needs a durable HTTPS VIDEO_URL." >&2
      missing=1
    }
    rg --quiet '^WSO2_CONTRIBUTION_URL=https://github\.com/wso2/.+/(issues|pull)/[0-9]+$' \
      "${manifest}" || {
      echo "manifest.txt needs a verifiable WSO2 issue or pull-request URL." >&2
      missing=1
    }
    rg --quiet '^PRIVILEGED_ADMIN_FLOW=passed$' "${manifest}" || {
      echo "manifest.txt must confirm the privileged browser-admin flow passed." >&2
      missing=1
    }
    rg --quiet '^COMMIT_SHA=[0-9a-f]{40}$' "${manifest}" || {
      echo "manifest.txt needs the demonstrated 40-character COMMIT_SHA." >&2
      missing=1
    }
  fi

  if ((missing > 0)); then
    echo "Release evidence is incomplete; do not tag the release." >&2
    return 1
  fi

  echo "Runtime evidence manifest is complete. Visually review every capture for secrets before tagging."
}

case "${audit_target}" in
  source)
    check_source_release_files
    ;;
  evidence)
    check_runtime_evidence
    ;;
  all)
    check_source_release_files
    check_runtime_evidence
    ;;
  *)
    echo "usage: $0 [source|evidence|all]" >&2
    exit 2
    ;;
esac

echo "Day 42 release audit passed (${audit_target})."
