#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

MIGRATIONS_DIR="${PROJECT_ROOT}/database/migrations"
MIGRATION_LOCK_KEY="182736451"
ACTION="${1:-up}"

require_database

db_psql --quiet <<'SQL'
CREATE TABLE IF NOT EXISTS schema_migrations (
    version    text PRIMARY KEY,
    applied_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);
SQL

apply_up() {
    local file="$1"
    local version
    version="$(basename "${file}" .up.sql)"

    if [[ ! "${version}" =~ ^V[0-9]{3}__[a-z0-9_]+$ ]]; then
        printf 'error: invalid migration filename: %s\n' "${file}" >&2
        return 1
    fi

    {
        printf 'BEGIN;\nSELECT pg_advisory_xact_lock(%s);\n' "${MIGRATION_LOCK_KEY}"
        printf "SELECT NOT EXISTS (SELECT 1 FROM schema_migrations WHERE version = '%s') AS apply_migration \\gset\n" "${version}"
        printf '\\if :apply_migration\n'
        sed -e '/^[[:space:]]*BEGIN[[:space:]]*;[[:space:]]*$/Id' \
            -e '/^[[:space:]]*COMMIT[[:space:]]*;[[:space:]]*$/Id' "${file}"
        printf "\nINSERT INTO schema_migrations (version) VALUES ('%s');\n" "${version}"
        printf '\\echo applied %s\n\\else\n\\echo already applied %s\n\\endif\nCOMMIT;\n' \
            "${version}" "${version}"
    } | db_psql --quiet
}

apply_down() {
    local version file
    version="$(db_psql --tuples-only --no-align --command \
        'SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1')"

    if [[ -z "${version}" ]]; then
        printf 'no migrations to roll back\n'
        return 0
    fi
    if [[ ! "${version}" =~ ^V[0-9]{3}__[a-z0-9_]+$ ]]; then
        printf 'error: migration ledger contains an invalid version: %s\n' "${version}" >&2
        return 1
    fi

    file="${MIGRATIONS_DIR}/${version}.down.sql"
    if [[ ! -f "${file}" ]]; then
        printf 'error: missing down migration: %s\n' "${file}" >&2
        return 1
    fi

    {
        printf 'BEGIN;\nSELECT pg_advisory_xact_lock(%s);\n' "${MIGRATION_LOCK_KEY}"
        printf "SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE version = '%s') AS revert_migration \\gset\n" "${version}"
        printf '\\if :revert_migration\n'
        sed -e '/^[[:space:]]*BEGIN[[:space:]]*;[[:space:]]*$/Id' \
            -e '/^[[:space:]]*COMMIT[[:space:]]*;[[:space:]]*$/Id' "${file}"
        printf "\nDELETE FROM schema_migrations WHERE version = '%s';\n" "${version}"
        printf '\\echo reverted %s\n\\else\n\\echo already reverted %s\n\\endif\nCOMMIT;\n' \
            "${version}" "${version}"
    } | db_psql --quiet
}

case "${ACTION}" in
    up)
        shopt -s nullglob
        up_files=("${MIGRATIONS_DIR}"/V*.up.sql)
        if ((${#up_files[@]} == 0)); then
            printf 'error: no up migrations found in %s\n' "${MIGRATIONS_DIR}" >&2
            exit 1
        fi
        for file in "${up_files[@]}"; do
            apply_up "${file}"
        done
        ;;
    down)
        apply_down
        ;;
    *)
        printf 'usage: %s [up|down]\n' "$0" >&2
        exit 2
        ;;
esac
