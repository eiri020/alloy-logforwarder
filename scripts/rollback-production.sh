#!/usr/bin/env bash
set -euo pipefail

ha_ssh_target="${HA_SSH_TARGET:-root@192.168.64.10}"
app_slug="${HA_APP_SLUG:-local_alloy_logforwarder}"
unmanaged_container="${HA_UNMANAGED_ALLOY_CONTAINER:-mon-03-05-ha-alloy}"
mode="${1:-}"

commands=(
  "ha apps stop ${app_slug} || true"
  "docker start ${unmanaged_container}"
  "docker ps --filter name=${unmanaged_container}"
  "ha apps info ${app_slug} --raw-json || true"
)

if [[ "$mode" == "--dry-run" ]]; then
  echo "Rollback target: ${ha_ssh_target}"
  for command in "${commands[@]}"; do
    printf 'DRY-RUN ssh %q %q\n' "$ha_ssh_target" "$command"
  done
  exit 0
fi

echo "Stopping managed Home Assistant app on ${ha_ssh_target}: ${app_slug}"
# shellcheck disable=SC2029
ssh "$ha_ssh_target" "${commands[0]}"

echo "Starting unmanaged Alloy fallback container on ${ha_ssh_target}: ${unmanaged_container}"
# shellcheck disable=SC2029
ssh "$ha_ssh_target" "${commands[1]}"

echo "Verifying unmanaged Alloy fallback container"
# shellcheck disable=SC2029
ssh "$ha_ssh_target" "${commands[2]}"

echo "Managed app state after rollback"
# shellcheck disable=SC2029
ssh "$ha_ssh_target" "${commands[3]}"
