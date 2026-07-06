#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

target="${HA_DEPLOY_TARGET:-root@192.168.64.10:/addons/alloy-logforwarder/}"
mode="${1:-}"

rsync_args=(
  --archive
  --delete
  --exclude ".devcontainer/"
  --exclude ".vscode/"
  --exclude ".git/"
)

if [ "$mode" = "--dry-run" ]; then
  rsync_args+=(--dry-run --itemize-changes)
fi

if [ ! -f config.yaml ] || [ ! -f Dockerfile ] || [ ! -f run.sh ]; then
  echo "App skeleton is incomplete. Expected config.yaml, Dockerfile and run.sh." >&2
  echo "Use --dry-run after the skeleton exists to preview deploy changes." >&2
  exit 2
fi

rsync "${rsync_args[@]}" ./ "$target"
