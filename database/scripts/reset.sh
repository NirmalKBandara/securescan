#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_database

db_psql --quiet <<'SQL'
DROP SCHEMA public CASCADE;
CREATE SCHEMA AUTHORIZATION CURRENT_USER;
GRANT USAGE ON SCHEMA public TO PUBLIC;
SQL

"${SCRIPT_DIR}/migrate.sh" up
"${SCRIPT_DIR}/seed.sh"
printf 'development database reset, migrated, and seeded\n'
