#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

image_name="${IMAGE_NAME:-alloy-logforwarder:dev}"

if [ ! -f Dockerfile ]; then
  echo "Dockerfile is missing. Add the app skeleton before running a smoke test." >&2
  exit 2
fi

docker run --rm --entrypoint /bin/bash "$image_name" -lc \
  'alloy --version >/dev/null && jq --version >/dev/null'

tmp_dir="$(mktemp -d)"
container_id=""
trap 'docker rm -f "$container_id" >/dev/null 2>&1 || true; rm -rf "$tmp_dir"' EXIT

cat >"$tmp_dir/options.json" <<'JSON'
{
  "loki_url": "http://127.0.0.1:9/loki/api/v1/push",
  "log_level": "info",
  "source_path": "/data/smoke.log",
  "host_label": "ha-debug",
  "site_label": "javastraat",
  "service_label": "homeassistant",
  "app_label": "homeassistant",
  "source_type_label": "ha-core",
  "environment_label": "test",
  "stream_label": "events",
  "custom_alloy_config_glob": "/data/snippets/*.alloy",
  "sources": []
}
JSON

cat >"$tmp_dir/smoke.log" <<'EOF'
2026-07-05 00:00:00.000 INFO (MainThread) [smoke.test] Alloy smoke test
EOF

cat >"$tmp_dir/custom-app.log" <<'EOF'
2026-07-05 00:00:01.000 WARNING (MainThread) [custom.app] Custom app smoke test
EOF

mkdir -p "$tmp_dir/snippets"
cp snippets/homeassistant-core.alloy "$tmp_dir/snippets/homeassistant-core.alloy"
cp snippets/zigbee2mqtt.alloy "$tmp_dir/snippets/zigbee2mqtt.alloy"

cat >"$tmp_dir/snippets/custom-app.alloy" <<'EOF'
loki.source.file "custom_app" {
  targets = [{
    __path__ = "/data/custom-app.log",
  }]
  forward_to = [loki.process.custom_app.receiver]
}

loki.process "custom_app" {
  stage.static_labels {
    values = {
      host        = "ha-debug",
      site        = "javastraat",
      service     = "custom-app",
      app         = "custom-app",
      source_type = "ha-app",
      environment = "test",
      stream      = "events",
      severity    = "info",
    }
  }

  forward_to = [loki.write.default.receiver]
}
EOF

container_id="$(docker run -d -v "$tmp_dir:/data:ro" "$image_name")"

for _ in 1 2 3 4 5 6 7 8 9 10; do
  logs="$(docker logs "$container_id" 2>&1)"
  if printf '%s' "$logs" | grep -q "Rendered Alloy config" &&
    printf '%s' "$logs" | grep -q "No generated sources configured" &&
    printf '%s' "$logs" | grep -q "Appending Alloy snippet for custom" &&
    printf '%s' "$logs" | grep -q "homeassistant-core.alloy" &&
    printf '%s' "$logs" | grep -q "zigbee2mqtt.alloy" &&
    printf '%s' "$logs" | grep -q "now listening for http traffic"; then
    echo "Smoke test passed: container started and emitted startup log."
    exit 0
  fi
  sleep 1
done

echo "Smoke test failed: startup log not found." >&2
docker logs "$container_id" >&2 || true
exit 1
