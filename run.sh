#!/usr/bin/env bash
set -euo pipefail

show_help() {
  cat <<'EOF'
Alloy Logforwarder Home Assistant app.

Reads Home Assistant log lines and forwards them to Loki via Grafana Alloy.
EOF
}

log() {
  printf '[alloy-logforwarder] %s\n' "$*"
}

require_tool() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    log "Required tool missing: ${tool}"
    exit 2
  fi
}

read_runtime_secret() {
  local key="$1"
  local value="${!key:-}"
  local s6_env_file="/var/run/s6/container_environment/${key}"

  if [[ -n "$value" ]]; then
    printf '%s' "$value"
    return
  fi

  if [[ -r "$s6_env_file" ]]; then
    tr -d '\000' <"$s6_env_file"
  fi
}

read_option() {
  local key="$1"
  local fallback="$2"

  if [[ ! -f /data/options.json ]]; then
    printf '%s' "$fallback"
    return
  fi

  local value
  value="$(jq -r --arg key "$key" '.[$key] // empty' /data/options.json 2>/dev/null || true)"
  if [[ -z "$value" || "$value" == "null" ]]; then
    printf '%s' "$fallback"
    return
  fi

  printf '%s' "$value"
}

escape_for_alloy() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

normalize_log_level() {
  local level="$1"
  case "${level,,}" in
    trace|debug|info|warn|error)
      printf '%s' "${level,,}"
      ;;
    *)
      printf '%s' "info"
      ;;
  esac
}

option_enabled() {
  local key="$1"
  local fallback="$2"
  local value

  value="$(read_option "$key" "$fallback")"
  case "${value,,}" in
    true|1|yes|on)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

normalize_interval() {
  local value="$1"

  if [[ "$value" =~ ^[0-9]+$ ]] && [[ "$value" -ge 5 ]]; then
    printf '%s' "$value"
    return
  fi

  printf '%s' "30"
}

sanitize_component_name() {
  local value="$1"
  local index="$2"
  local sanitized

  sanitized="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_' '_')"
  sanitized="${sanitized##_}"
  sanitized="${sanitized%%_}"

  if [[ -z "$sanitized" || "$sanitized" =~ ^[0-9] ]]; then
    sanitized="source_${index}_${sanitized}"
  fi

  printf '%s' "$sanitized"
}

source_rows_json() {
  local options_file="${1:-/data/options.json}"

  if [[ -f "$options_file" ]]; then
    jq -c '
      def legacy:
        [{
          preset: "homeassistant",
          name: "homeassistant",
          enabled: true,
          path: (.source_path // "/config/home-assistant.log"),
          service: (.service_label // "homeassistant"),
          app: (.app_label // "homeassistant"),
          source_type: (.source_type_label // "ha-core"),
          stream: (.stream_label // "events")
        }];

      def defaults($preset):
        if $preset == "homeassistant" then {
          name: "homeassistant",
          path: "/config/home-assistant.log",
          service: "homeassistant",
          app: "homeassistant",
          source_type: "ha-core",
          stream: "events"
        } elif $preset == "zigbee2mqtt" then {
          name: "zigbee2mqtt",
          path: "/addon_configs/45df7312_zigbee2mqtt/log/zigbee2mqtt.log",
          service: "zigbee2mqtt",
          app: "zigbee2mqtt",
          source_type: "zigbee2mqtt",
          stream: "events"
        } elif $preset == "mosquitto" then {
          name: "mosquitto",
          path: "/addon_configs/core_mosquitto/mosquitto.log",
          service: "mosquitto",
          app: "mosquitto",
          source_type: "mosquitto",
          stream: "events"
        } else {
          name: "custom",
          path: "",
          service: "custom",
          app: "custom",
          source_type: "ha-app",
          stream: "events"
        } end;

      def normalize:
        . as $source
        | ($source.preset // "custom") as $preset
        | defaults($preset) + $source
        | .preset = $preset
        | .enabled = (.enabled // true);

      (if has("sources") and (.sources | type) == "array" then
        .sources
      else
        legacy
      end)
      | map(normalize)
      | map(select(.enabled == true))
    ' "$options_file"
  else
    jq -n -c '[{
      preset: "homeassistant",
      name: "homeassistant",
      enabled: true,
      path: "/config/home-assistant.log",
      service: "homeassistant",
      app: "homeassistant",
      source_type: "ha-core",
      stream: "events"
    }]'
  fi
}

append_source_config() {
  local config_path="$1"
  local component="$2"
  local source_path="$3"
  local host_label="$4"
  local site_label="$5"
  local environment_label="$6"
  local stream_label="$7"
  local service_label="$8"
  local app_label="$9"
  local source_type_label="${10}"

  cat >>"$config_path" <<EOF

loki.source.file "${component}" {
  targets = [{
    __path__ = "$(escape_for_alloy "$source_path")",
  }]
  forward_to = [loki.process.${component}.receiver]
}

loki.process "${component}" {
  stage.regex {
    expression = "(?i)^(?:[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(?:[.][0-9]+)?(?:Z|[+-][0-9]{2}:?[0-9]{2})?[[:space:]]+)?(?P<raw_level>debug|info|warning|warn|error|critical|fatal)(?:[[:space:]]|$).*"
  }

  stage.template {
    source   = "severity"
    template = "{{- if .raw_level -}}{{- if eq (ToLower .raw_level) \"warning\" -}}warn{{- else if eq (ToLower .raw_level) \"critical\" -}}fatal{{- else -}}{{ToLower .raw_level}}{{- end -}}{{- else -}}info{{- end -}}"
  }

  stage.static_labels {
    values = {
      host        = "$(escape_for_alloy "$host_label")",
      site        = "$(escape_for_alloy "$site_label")",
      service     = "$(escape_for_alloy "$service_label")",
      app         = "$(escape_for_alloy "$app_label")",
      source_type = "$(escape_for_alloy "$source_type_label")",
      environment = "$(escape_for_alloy "$environment_label")",
      stream      = "$(escape_for_alloy "$stream_label")",
    }
  }

  stage.labels {
    values = {
      severity = "severity",
    }
  }

  forward_to = [loki.write.default.receiver]
}
EOF
}

append_alloy_snippet() {
  local config_path="$1"
  local snippet_path="$2"
  local label="$3"

  if [[ ! -f "$snippet_path" ]]; then
    log "Alloy snippet not found for ${label}: ${snippet_path}"
    exit 2
  fi

  log "Appending Alloy snippet for ${label}: ${snippet_path}"
  {
    printf '\n// Begin snippet: %s (%s)\n' "$label" "$snippet_path"
    cat "$snippet_path"
    printf '\n// End snippet: %s\n' "$label"
  } >>"$config_path"
}

render_alloy_snippet() {
  local config_path="$1"
  local snippet_path="$2"
  local label="$3"
  local source_path="$4"
  local host_label="$5"
  local site_label="$6"
  local environment_label="$7"
  local stream_label="$8"
  local service_label="$9"
  local app_label="${10}"
  local source_type_label="${11}"
  local snippet

  if [[ ! -f "$snippet_path" ]]; then
    log "Alloy snippet not found for ${label}: ${snippet_path}"
    exit 2
  fi

  snippet="$(cat "$snippet_path")"
  snippet="${snippet//__SOURCE_PATH__/$(escape_for_alloy "$source_path")}"
  snippet="${snippet//__COMPONENT_NAME__/$(escape_for_alloy "$(sanitize_component_name "$label" "supervisor")")}"
  snippet="${snippet//__HOST_LABEL__/$(escape_for_alloy "$host_label")}"
  snippet="${snippet//__SITE_LABEL__/$(escape_for_alloy "$site_label")}"
  snippet="${snippet//__SERVICE_LABEL__/$(escape_for_alloy "$service_label")}"
  snippet="${snippet//__APP_LABEL__/$(escape_for_alloy "$app_label")}"
  snippet="${snippet//__SOURCE_TYPE_LABEL__/$(escape_for_alloy "$source_type_label")}"
  snippet="${snippet//__ENVIRONMENT_LABEL__/$(escape_for_alloy "$environment_label")}"
  snippet="${snippet//__STREAM_LABEL__/$(escape_for_alloy "$stream_label")}"

  log "Rendering Alloy snippet for ${label}: ${snippet_path}"
  {
    printf '\n// Begin rendered snippet: %s (%s)\n' "$label" "$snippet_path"
    printf '%s\n' "$snippet"
    printf '\n// End rendered snippet: %s\n' "$label"
  } >>"$config_path"
}

append_alloy_snippet_glob() {
  local config_path="$1"
  local snippet_glob="$2"
  local files=()
  local file

  mapfile -t files < <(compgen -G "$snippet_glob" | sort || true)

  if [[ "${#files[@]}" -eq 0 ]]; then
    log "No custom Alloy snippets matched: ${snippet_glob}"
    return
  fi

  for file in "${files[@]}"; do
    append_alloy_snippet "$config_path" "$file" "custom"
  done
}

supervisor_log_sources_json() {
  local options_file="${1:-/data/options.json}"

  if [[ ! -f "$options_file" ]]; then
    jq -n -c '[]'
    return
  fi

  jq -c '
    def normalize:
      . as $source
      | .enabled = (if has("enabled") then .enabled else true end)
      | .name = (.name // .slug // "supervisor_log")
      | .slug = (.slug // "core")
      | .endpoint = (.endpoint // "")
      | .path = (.path // (if .slug == "core" then "/tmp/alloy-logforwarder/homeassistant-core.log" else "/tmp/alloy-logforwarder/addons/" + .slug + ".log" end))
      | .snippet = (.snippet // (if .slug == "core" then "/etc/alloy-logforwarder/snippets/homeassistant-core.alloy" else "" end))
      | .service = (.service // .name)
      | .app = (.app // .name)
      | .source_type = (.source_type // .name)
      | .stream = (.stream // "events")
      | .poll_interval = (.poll_interval // 30);

    def legacy_core:
      [{
        enabled: true,
        name: "homeassistant_core_supervisor",
        slug: "core",
        endpoint: "core/logs",
        path: (.supervisor_core_logs_path // "/tmp/alloy-logforwarder/homeassistant-core.log"),
        snippet: "/etc/alloy-logforwarder/snippets/homeassistant-core.alloy",
        service: (.service_label // "homeassistant"),
        app: (.app_label // "homeassistant"),
        source_type: (.source_type_label // "ha-core"),
        stream: (.stream_label // "events"),
        poll_interval: (.supervisor_core_logs_poll_interval // 30)
      }];

    if has("supervisor_log_sources") and (.supervisor_log_sources | type) == "array" then
      (.supervisor_log_sources | map(normalize) | map(select(.enabled == true))) as $configured
      | if ($configured | length) > 0 then
          $configured
        elif (.supervisor_core_logs_enabled // false) == true then
          legacy_core
        else
          []
        end
    elif (.supervisor_core_logs_enabled // false) == true then
      legacy_core
    else
      []
    end
  ' "$options_file"
}

supervisor_logs_url() {
  local slug="$1"
  local endpoint="${2:-}"

  if [[ -n "$endpoint" ]]; then
    printf 'http://supervisor/%s' "$endpoint"
    return
  fi

  if [[ "$slug" == "core" ]]; then
    printf '%s' "${SUPERVISOR_CORE_LOGS_URL:-http://supervisor/core/logs}"
    return
  fi

  case "$slug" in
    supervisor|host|dns|audio|multicast)
      printf 'http://supervisor/%s/logs' "$slug"
      return
      ;;
  esac

  printf 'http://supervisor/addons/%s/logs' "$slug"
}

start_supervisor_logs_collector() {
  local name="$1"
  local slug="$2"
  local output_path="$3"
  local poll_interval="$4"
  local endpoint="${5:-}"
  local supervisor_url
  local supervisor_token
  local state_dir="/tmp/alloy-logforwarder"
  local seen_file

  supervisor_url="$(supervisor_logs_url "$slug" "$endpoint")"
  seen_file="${state_dir}/$(sanitize_component_name "$name" "supervisor")-log-lines.sha256"

  supervisor_token="$(read_runtime_secret "SUPERVISOR_TOKEN")"
  if [[ -z "$supervisor_token" ]]; then
    supervisor_token="$(read_runtime_secret "HASSIO_TOKEN")"
  fi

  if [[ -z "$supervisor_token" ]]; then
    log "No Supervisor API token is available; expected SUPERVISOR_TOKEN/HASSIO_TOKEN env or s6 container environment file."
    exit 2
  fi

  mkdir -p "$(dirname "$output_path")" "$state_dir"
  touch "$output_path" "$seen_file"

  log "Starting Supervisor logs collector: name=${name} slug=${slug} endpoint=${endpoint:-auto} url=${supervisor_url} output=${output_path} interval=${poll_interval}s"

  (
    while true; do
      local tmp_file
      tmp_file="$(mktemp)"

      if curl -fsS \
        -H "Authorization: Bearer ${supervisor_token}" \
        "$supervisor_url" >"$tmp_file"; then
        awk '{ gsub(/\033\[[0-9;]*[A-Za-z]/, ""); print }' "$tmp_file" |
          while IFS= read -r line; do
            local digest
            [[ -z "$line" ]] && continue
            digest="$(printf '%s' "$line" | sha256sum | awk '{print $1}')"
            if grep -qxF "$digest" "$seen_file"; then
              continue
            fi
            printf '%s\n' "$digest" >>"$seen_file"
            printf '%s\n' "$line" >>"$output_path"
          done
      else
        log "Supervisor logs request failed for ${name}; retrying in ${poll_interval}s."
      fi

      rm -f "$tmp_file"
      sleep "$poll_interval"
    done
  ) &
}

render_alloy_config() {
  local config_path="$1"
  local loki_url="$2"
  local log_level="$3"
  local host_label="$4"
  local site_label="$5"
  local environment_label="$6"
  local sources_json="$7"
  local custom_alloy_config_glob="$8"
  local supervisor_sources_json="$9"

  cat >"$config_path" <<EOF
logging {
  level  = "$(escape_for_alloy "$log_level")"
  format = "logfmt"
}
EOF

  local source_count
  source_count="$(jq 'length' <<<"$sources_json")"
  if [[ "$source_count" -eq 0 ]]; then
    log "No generated sources configured."
  fi

  local index
  for ((index = 0; index < source_count; index++)); do
    local source_name
    local source_path
    local stream_label
    local service_label
    local app_label
    local source_type_label
    local component

    source_name="$(jq -r ".[$index].name // \"source_$index\"" <<<"$sources_json")"
    source_path="$(jq -r ".[$index].path // \"\"" <<<"$sources_json")"
    stream_label="$(jq -r ".[$index].stream // \"events\"" <<<"$sources_json")"
    service_label="$(jq -r ".[$index].service // .[$index].name // \"custom\"" <<<"$sources_json")"
    app_label="$(jq -r ".[$index].app // .[$index].name // \"custom\"" <<<"$sources_json")"
    source_type_label="$(jq -r ".[$index].source_type // \"ha-app\"" <<<"$sources_json")"
    component="$(sanitize_component_name "$source_name" "$index")"

    if [[ -z "$source_path" ]]; then
      log "Configured source '${source_name}' has no path."
      exit 2
    fi

    log "Configured source[$index]: name=${source_name} path=${source_path} service=${service_label} app=${app_label} source_type=${source_type_label} stream=${stream_label}"

    if [[ ! -e "$source_path" ]]; then
      log "Source file does not exist yet: ${source_path}. Alloy will wait for matching targets."
    fi

    append_source_config \
      "$config_path" \
      "$component" \
      "$source_path" \
      "$host_label" \
      "$site_label" \
      "$environment_label" \
      "$stream_label" \
      "$service_label" \
      "$app_label" \
      "$source_type_label"
  done

  if [[ -n "$custom_alloy_config_glob" ]]; then
    append_alloy_snippet_glob "$config_path" "$custom_alloy_config_glob"
  fi

  local supervisor_source_count
  supervisor_source_count="$(jq 'length' <<<"$supervisor_sources_json")"
  if [[ "$supervisor_source_count" -eq 0 ]]; then
    log "No Supervisor log sources configured."
  fi

  local supervisor_index
  for ((supervisor_index = 0; supervisor_index < supervisor_source_count; supervisor_index++)); do
    local supervisor_name
    local supervisor_path
    local supervisor_snippet
    local supervisor_stream
    local supervisor_service
    local supervisor_app
    local supervisor_source_type

    supervisor_name="$(jq -r ".[$supervisor_index].name" <<<"$supervisor_sources_json")"
    supervisor_path="$(jq -r ".[$supervisor_index].path" <<<"$supervisor_sources_json")"
    supervisor_snippet="$(jq -r ".[$supervisor_index].snippet" <<<"$supervisor_sources_json")"
    supervisor_stream="$(jq -r ".[$supervisor_index].stream" <<<"$supervisor_sources_json")"
    supervisor_service="$(jq -r ".[$supervisor_index].service" <<<"$supervisor_sources_json")"
    supervisor_app="$(jq -r ".[$supervisor_index].app" <<<"$supervisor_sources_json")"
    supervisor_source_type="$(jq -r ".[$supervisor_index].source_type" <<<"$supervisor_sources_json")"

    if [[ -z "$supervisor_snippet" ]]; then
      log "Supervisor log source '${supervisor_name}' has no snippet."
      exit 2
    fi

    log "Configured Supervisor source[$supervisor_index]: name=${supervisor_name} path=${supervisor_path} service=${supervisor_service} app=${supervisor_app} source_type=${supervisor_source_type} stream=${supervisor_stream}"

    if [[ ! -e "$supervisor_path" ]]; then
      log "Supervisor spool file does not exist yet: ${supervisor_path}. The collector will create it."
    fi

    render_alloy_snippet \
      "$config_path" \
      "$supervisor_snippet" \
      "$supervisor_name" \
      "$supervisor_path" \
      "$host_label" \
      "$site_label" \
      "$environment_label" \
      "$supervisor_stream" \
      "$supervisor_service" \
      "$supervisor_app" \
      "$supervisor_source_type"
  done

  cat >>"$config_path" <<EOF

loki.write "default" {
  endpoint {
    url = "$(escape_for_alloy "$loki_url")"
  }
}
EOF
}

main() {
  if [[ "${1:-}" == "--help" ]]; then
    show_help
    exit 0
  fi

  require_tool alloy
  require_tool jq

  local loki_url
  local host_label
  local site_label
  local environment_label
  local log_level
  local sources_json
  local supervisor_sources_json
  local supervisor_source_count
  local custom_alloy_config_glob

  loki_url="$(read_option "loki_url" "http://192.168.64.50:3310/loki/api/v1/push")"
  host_label="$(read_option "host_label" "javastraat")"
  site_label="$(read_option "site_label" "javastraat")"
  environment_label="$(read_option "environment_label" "prod")"
  log_level="$(normalize_log_level "$(read_option "log_level" "info")")"
  sources_json="$(source_rows_json "/data/options.json")"
  supervisor_sources_json="$(supervisor_log_sources_json "/data/options.json")"
  supervisor_source_count="$(jq 'length' <<<"$supervisor_sources_json")"
  custom_alloy_config_glob="$(read_option "custom_alloy_config_glob" "/config/alloy-logforwarder/*.alloy")"

  log "Starting Alloy Logforwarder runtime"
  log "Loki endpoint: ${loki_url}"
  log "Configured log_level option: ${log_level}"
  log "Base labels: host=${host_label} site=${site_label} environment=${environment_label}"
  log "Supervisor log sources enabled: ${supervisor_source_count}"
  log "Custom Alloy config glob: ${custom_alloy_config_glob}"

  if [[ "$supervisor_source_count" -gt 0 ]]; then
    require_tool curl
    require_tool awk
    require_tool sha256sum
  fi

  local alloy_config
  alloy_config="/tmp/alloy-logforwarder.config.alloy"

  render_alloy_config \
    "$alloy_config" \
    "$loki_url" \
    "$log_level" \
    "$host_label" \
    "$site_label" \
    "$environment_label" \
    "$sources_json" \
    "$custom_alloy_config_glob" \
    "$supervisor_sources_json"

  log "Rendered Alloy config: ${alloy_config}"

  if [[ "${ALLOY_LOGFORWARDER_SMOKE:-}" == "1" ]]; then
    log "Smoke test mode completed"
    exit 0
  fi

  local supervisor_index
  for ((supervisor_index = 0; supervisor_index < supervisor_source_count; supervisor_index++)); do
    local supervisor_name
    local supervisor_slug
    local supervisor_path
    local supervisor_poll_interval
    local supervisor_endpoint

    supervisor_name="$(jq -r ".[$supervisor_index].name" <<<"$supervisor_sources_json")"
    supervisor_slug="$(jq -r ".[$supervisor_index].slug" <<<"$supervisor_sources_json")"
    supervisor_path="$(jq -r ".[$supervisor_index].path" <<<"$supervisor_sources_json")"
    supervisor_poll_interval="$(normalize_interval "$(jq -r ".[$supervisor_index].poll_interval // 30" <<<"$supervisor_sources_json")")"
    supervisor_endpoint="$(jq -r ".[$supervisor_index].endpoint // \"\"" <<<"$supervisor_sources_json")"

    start_supervisor_logs_collector \
      "$supervisor_name" \
      "$supervisor_slug" \
      "$supervisor_path" \
      "$supervisor_poll_interval" \
      "$supervisor_endpoint"
  done

  exec alloy run \
    "$alloy_config" \
    --disable-reporting \
    --server.http.listen-addr=127.0.0.1:12345
}

main "$@"
