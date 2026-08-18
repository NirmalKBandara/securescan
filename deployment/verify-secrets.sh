#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repository_root}"

tracked_files="$(mktemp)"
trap 'rm -f "${tracked_files}"' EXIT
git ls-files -z ':!deployment/verify-secrets.sh' >"${tracked_files}"

patterns=(
  '-''----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
  'AKIA[0-9A-Z]{16}'
  'gh[pousr]_[A-Za-z0-9_]{36,}'
  'xox[baprs]-[A-Za-z0-9-]{10,}'
)

for pattern in "${patterns[@]}"; do
  if xargs -0 -r grep -IlE -- "${pattern}" <"${tracked_files}" | grep -q .; then
    echo "Potential credential material matched: ${pattern}" >&2
    xargs -0 -r grep -IlE -- "${pattern}" <"${tracked_files}" >&2
    exit 1
  fi
  if git log --all --format= --no-ext-diff -p | grep -E -- "${pattern}" >/dev/null; then
    echo "Potential credential material exists in Git history: ${pattern}" >&2
    exit 1
  fi
done

for forbidden in \
  'deployment/.env' \
  'frontend/.env.local' \
  'ballerina-api/Config.toml'; do
  if git ls-files --error-unmatch "${forbidden}" >/dev/null 2>&1; then
    echo "Local configuration must not be tracked: ${forbidden}" >&2
    exit 1
  fi
done

echo "Tracked-file secret checks passed."
