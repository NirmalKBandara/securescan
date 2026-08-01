#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
COMPOSE_FILE="${PROJECT_ROOT}/deployment/compose.yaml"
DB_USER="${POSTGRES_USER:-securescan}"
DB_NAME="${POSTGRES_DB:-securescan_dev}"

require_database() {
    if ! command -v docker >/dev/null 2>&1; then
        printf 'error: docker is required; install Docker with the Compose plugin first\n' >&2
        return 1
    fi

    if ! docker compose version >/dev/null 2>&1; then
        printf 'error: the Docker Compose plugin is required\n' >&2
        return 1
    fi

    if ! docker compose -f "${COMPOSE_FILE}" exec -T postgres \
        pg_isready --username "${DB_USER}" --dbname "${DB_NAME}" >/dev/null 2>&1; then
        printf 'error: PostgreSQL is not ready; run docker compose -f deployment/compose.yaml up -d --wait\n' >&2
        return 1
    fi
}

db_psql() {
    docker compose -f "${COMPOSE_FILE}" exec -T postgres \
        psql --no-psqlrc --set=ON_ERROR_STOP=1 \
        --username "${DB_USER}" --dbname "${DB_NAME}" "$@"
}
