#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="${1:-all}"

run_go() {
  echo "==> Go scanner"
  (
    cd "${repository_root}/scanner-engine"
    go vet ./...
    go test -race ./...
    go build ./...
  )
}

run_ballerina() {
  echo "==> Ballerina API"
  (
    cd "${repository_root}/ballerina-api"
    bal test
    bal build
  )
}

run_frontend() {
  echo "==> Next.js frontend"
  (
    cd "${repository_root}/frontend"
    npm test
    npm run lint
    npm run typecheck
    NEXT_PUBLIC_API_BASE_URL=/backend npm run build
  )
}

run_repository_checks() {
  echo "==> Repository checks"
  while IFS= read -r -d '' script; do
    bash -n "${script}"
  done < <(find "${repository_root}" -path '*/node_modules' -prune -o \
    -path '*/.git' -prune -o -type f -name '*.sh' -print0)
  "${repository_root}/scripts/verify-docs.sh"
  "${repository_root}/deployment/verify-secrets.sh"
  git -C "${repository_root}" diff --check
}

case "${target}" in
  all)
    run_go
    run_ballerina
    run_frontend
    run_repository_checks
    ;;
  go) run_go ;;
  ballerina) run_ballerina ;;
  frontend) run_frontend ;;
  repository) run_repository_checks ;;
  *)
    echo "usage: $0 [all|go|ballerina|frontend|repository]" >&2
    exit 2
    ;;
esac

echo "Day 38 verification passed (${target})."
