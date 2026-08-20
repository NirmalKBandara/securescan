#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failure_count=0

while IFS=: read -r source line match; do
  target="${match#*](}"
  target="${target%)}"
  target="${target#<}"
  target="${target%>}"

  case "${target}" in
    ""|'#'*|http://*|https://*|mailto:*|tel:*)
      continue
      ;;
  esac

  target="${target%%#*}"
  target="${target%%\?*}"
  if [[ -z "${target}" ]]; then
    continue
  fi

  if [[ "${target}" == /* ]]; then
    resolved="$(realpath -m -- "${repository_root}/${target#/}")"
  else
    resolved="$(realpath -m -- "${repository_root}/$(dirname "${source}")/${target}")"
  fi

  if [[ "${resolved}" != "${repository_root}" && "${resolved}" != "${repository_root}/"* ]]; then
    printf '%s:%s: local documentation link leaves the repository: %s\n' \
      "${source}" "${line}" "${target}" >&2
    failure_count=$((failure_count + 1))
  elif [[ ! -e "${resolved}" ]]; then
    printf '%s:%s: broken local documentation link: %s\n' \
      "${source}" "${line}" "${target}" >&2
    failure_count=$((failure_count + 1))
  fi
done < <(
  cd "${repository_root}"
  rg --no-heading --line-number --only-matching \
    '\[[^\[\]]+\]\([^\)]+\)' \
    --glob '*.md' \
    --glob '!frontend/node_modules/**' \
    . || true
)

if ((failure_count > 0)); then
  printf 'Documentation verification failed with %d broken local link(s).\n' \
    "${failure_count}" >&2
  exit 1
fi

documentation_index="${repository_root}/docs/README.md"
while IFS= read -r -d '' document; do
  relative_path="${document#"${repository_root}/docs/"}"
  if [[ "${relative_path}" == "README.md" ]]; then
    continue
  fi
  if ! rg --fixed-strings --quiet -- "](${relative_path}" \
      "${documentation_index}"; then
    printf 'docs/%s: not linked from docs/README.md\n' \
      "${relative_path}" >&2
    failure_count=$((failure_count + 1))
  fi
done < <(find "${repository_root}/docs" -type f -name '*.md' -print0)

if ((failure_count > 0)); then
  printf 'Documentation verification failed with %d issue(s).\n' \
    "${failure_count}" >&2
  exit 1
fi

echo "Documentation verification passed."
