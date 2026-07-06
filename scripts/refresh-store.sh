#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

ha_ssh_target="${HA_SSH_TARGET:-}"

if [ -z "$ha_ssh_target" ]; then
  echo "HA_SSH_TARGET is required." >&2
  echo "Example: HA_SSH_TARGET=root@homeassistant.local $0" >&2
  exit 2
fi

slug="$(
  python3 - <<'PY'
from pathlib import Path

import yaml

config = yaml.safe_load(Path("config.yaml").read_text())
print(config["slug"])
PY
)"

name="$(
  python3 - <<'PY'
from pathlib import Path

import yaml

config = yaml.safe_load(Path("config.yaml").read_text())
print(config["name"])
PY
)"

echo "Reloading Home Assistant app store on ${ha_ssh_target}"
ssh "$ha_ssh_target" "ha store reload >/dev/null"

store_json="$(ssh "$ha_ssh_target" "ha store apps --raw-json")"

if printf '%s' "$store_json" | grep -q "$slug"; then
  echo "Home Assistant store sees local app slug: ${slug}"
  exit 0
fi

if printf '%s' "$store_json" | grep -q "$name"; then
  echo "Home Assistant store sees local app name: ${name}"
  exit 0
fi

echo "Home Assistant store does not list ${name} (${slug}) yet." >&2
echo "Check that the app files exist under /addons/alloy-logforwarder and inspect the Supervisor logs." >&2
exit 1
