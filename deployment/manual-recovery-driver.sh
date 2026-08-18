#!/usr/bin/env bash
set -euo pipefail

scenario="${1:-}"
subject="${2:-}"

if [[ ! -r /dev/tty ]]; then
  echo "The manual recovery driver needs an interactive terminal." >&2
  exit 1
fi

case "${scenario}" in
  bootstrap)
    cat >/dev/tty <<'EOF'
Complete the one-time WSO2 setup now:
  1. Replace the bootstrap administrator password.
  2. Create securescan-user and securescan-admin roles and test users.
  3. Register the exact frontend callback/logout URLs and update deployment/.env.
  4. Import/publish the API, configure scopes and subscriptions, and install throttling policies.
  5. Create an allowed target you own and are authorized to scan.
EOF
    read -r -p "Type READY after the setup is complete: " answer </dev/tty
    [[ "${answer}" == "READY" ]] || exit 1
    ;;
  complete-flow)
    echo "Complete login -> authorized scan -> terminal results flow ${subject} in the browser." >/dev/tty
    read -r -p "Paste the completed public scan UUID: " scan_id </dev/tty
    if [[ ! "${scan_id}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]]; then
      echo "A valid completed scan UUID is required." >&2
      exit 1
    fi
    printf '%s\n' "${scan_id}"
    ;;
  dependency-down)
    echo "Verify ${subject} produces a bounded, safe user-facing failure (no stack trace or credential leak)." >/dev/tty
    read -r -p "Type SAFE after observing the expected failure: " answer </dev/tty
    [[ "${answer}" == "SAFE" ]] || exit 1
    ;;
  *)
    echo "usage: $0 bootstrap | complete-flow PASS | dependency-down SERVICE" >&2
    exit 2
    ;;
esac
