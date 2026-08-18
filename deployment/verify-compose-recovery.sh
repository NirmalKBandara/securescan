#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
environment_file="${repository_root}/deployment/.env"
driver="${SECURESCAN_RECOVERY_DRIVER:-${repository_root}/deployment/manual-recovery-driver.sh}"
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
resource_prefix="securescan-recovery-${run_id,,}"
evidence_dir="${RECOVERY_EVIDENCE_DIR:-${repository_root}/deployment/evidence/${run_id}}"
mkdir -p "${evidence_dir}"

if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
  echo "Docker with the Compose plugin is required for Day 37 recovery verification." >&2
  exit 1
fi
if [[ ! -x "${driver}" ]]; then
  echo "Recovery driver is not executable: ${driver}" >&2
  exit 1
fi

"${repository_root}/deployment/validate-config.sh" "${environment_file}"
"${repository_root}/deployment/verify-secrets.sh"

compose=(
  env
  COMPOSE_PROJECT_NAME="${resource_prefix}"
  POSTGRES_VOLUME_NAME="${resource_prefix}-postgres"
  IDENTITY_NETWORK_NAME="${resource_prefix}-identity"
  GATEWAY_NETWORK_NAME="${resource_prefix}-gateway"
  INTEGRATION_NETWORK_NAME="${resource_prefix}-integration"
  SCANNER_NETWORK_NAME="${resource_prefix}-scanner"
  DATA_NETWORK_NAME="${resource_prefix}-data"
  docker compose --env-file "${environment_file}"
  --file "${repository_root}/deployment/compose.yaml"
)

cleanup() {
  if [[ "${KEEP_RECOVERY_STACK:-false}" == "true" ]]; then
    echo "Recovery stack retained: ${resource_prefix}" >&2
  else
    "${compose[@]}" down --remove-orphans >/dev/null 2>&1 || true
    docker volume rm "${resource_prefix}-postgres" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

record() {
  printf '%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" \
    | tee -a "${evidence_dir}/timeline.tsv"
}

record "cold-start-begin"
start_seconds="$(date +%s)"
"${compose[@]}" config --quiet
"${compose[@]}" up --detach --build --wait
cold_start_seconds="$(( $(date +%s) - start_seconds ))"
record "cold-start-ready seconds=${cold_start_seconds}"
"${compose[@]}" ps >"${evidence_dir}/initial-services.txt"

migration_count="$("${compose[@]}" exec -T postgres sh -c \
  'psql --no-psqlrc --tuples-only --no-align --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --command "SELECT count(*) FROM schema_migrations;"' \
  | tr -d '[:space:]')"
if [[ "${migration_count}" != "6" ]]; then
  echo "Fresh database did not record all six migrations (got ${migration_count})." >&2
  exit 1
fi
record "fresh-database migrations=${migration_count}"

"${driver}" bootstrap
scan_one="$("${driver}" complete-flow 1)"
scan_two="$("${driver}" complete-flow 2)"
for scan_id in "${scan_one}" "${scan_two}"; do
  if [[ ! "${scan_id}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]]; then
    echo "Recovery driver returned an invalid scan UUID: ${scan_id}" >&2
    exit 1
  fi
done
printf '%s\n%s\n' "${scan_one}" "${scan_two}" >"${evidence_dir}/completed-scan-ids.txt"
record "two-login-to-results-flows-complete"

"${compose[@]}" down
record "normal-stop-complete"
restart_seconds="$(date +%s)"
"${compose[@]}" up --detach --wait
restart_seconds="$(( $(date +%s) - restart_seconds ))"
record "restart-ready seconds=${restart_seconds}"

for scan_id in "${scan_one}" "${scan_two}"; do
  persisted="$("${compose[@]}" exec -T postgres sh -c \
    'psql --no-psqlrc --tuples-only --no-align --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --command "$1"' \
    sh "SELECT count(*) FROM scan_jobs WHERE id = '${scan_id}'::uuid;" \
    | tr -d '[:space:]')"
  if [[ "${persisted}" != "1" ]]; then
    echo "Scan ${scan_id} was not retained after restart." >&2
    exit 1
  fi
done
record "scan-results-persisted-after-restart"

for service in scanner-engine postgres api-manager identity-server; do
  "${compose[@]}" stop --timeout 15 "${service}"
  "${driver}" dependency-down "${service}"
  "${compose[@]}" up --detach --wait "${service}"
  record "dependency-recovered service=${service}"
done

"${compose[@]}" ps >"${evidence_dir}/final-services.txt"
record "day-37-recovery-check-passed"
echo "Evidence written to ${evidence_dir}."
