#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

files=()
while IFS= read -r file; do
  files+=("$file")
done < <(find . -type f \( -name "*.yaml" -o -name "*.yml" \) -print | sort)

if [ "${#files[@]}" -eq 0 ]; then
  echo "No YAML files found."
  exit 0
fi

yamllint "${files[@]}"
