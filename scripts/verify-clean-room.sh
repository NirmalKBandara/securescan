#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
verification_target="${1:-repository}"

case "${verification_target}" in
  repository|go|ballerina|frontend|all) ;;
  *)
    echo "usage: $0 [repository|go|ballerina|frontend|all]" >&2
    exit 2
    ;;
esac

if [[ -n "$(git -C "${repository_root}" status --porcelain)" ]]; then
  echo "Clean-room verification requires a clean source worktree." >&2
  exit 1
fi

clean_room="$(mktemp -d -t securescan-clean-room.XXXXXXXX)"
cleanup() {
  rm -rf -- "${clean_room}"
}
trap cleanup EXIT

git -C "${repository_root}" archive --format=tar HEAD | tar -xf - -C "${clean_room}"

# The repository gate uses Git's whitespace checker. Recreate a local snapshot
# repository without copying the source checkout's history or ignored files.
git -C "${clean_room}" init --quiet
git -C "${clean_room}" add .
git -C "${clean_room}" \
  -c user.name=SecureScan-Clean-Room \
  -c user.email=clean-room@localhost \
  commit --quiet -m snapshot

if [[ "${verification_target}" == "frontend" ||
      "${verification_target}" == "all" ]]; then
  (
    cd "${clean_room}/frontend"
    npm ci
  )
fi

echo "Clean-room source: committed HEAD $(git -C "${repository_root}" rev-parse --short HEAD)"
echo "Clean-room target: ${verification_target}"
"${clean_room}/scripts/verify.sh" "${verification_target}"

echo "Clean-room verification passed (${verification_target})."
