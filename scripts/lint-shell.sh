#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

files=()
while IFS= read -r file; do
  files+=("$file")
done < <(find . -type f -name "*.sh" -print | sort)

if [ "${#files[@]}" -eq 0 ]; then
  echo "No shell files found."
  exit 0
fi

shellcheck "${files[@]}"
