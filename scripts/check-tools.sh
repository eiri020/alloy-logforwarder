#!/usr/bin/env bash
set -euo pipefail

missing=0

for tool in docker jq python3 rsync shellcheck yamllint; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf '%-12s %s\n' "$tool" "$(command -v "$tool")"
  else
    printf '%-12s missing\n' "$tool" >&2
    missing=1
  fi
done

if ! python3 -c 'import yaml' >/dev/null 2>&1; then
  echo "python3 yaml module missing" >&2
  missing=1
fi

exit "$missing"
