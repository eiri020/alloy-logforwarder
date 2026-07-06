# Alloy Logforwarder

Home Assistant app for forwarding Home Assistant logs to the central
Loki/Alloy logging stack.

## Status

Status: functional runtime is available. The app can read Home Assistant Core
logs through the Supervisor API and forward configurable HA app/add-on log
sources to Loki through separate `.alloy` snippets.

For HAOS/Supervised, the Supervisor API route is the preferred route for Home
Assistant Core logs. `home-assistant.log` is no longer used as the reliable
source there.

## Tested Platforms

This app has only been tested with Home Assistant OS (HAOS).

Other Home Assistant installation types, including Supervised, Container and
Core, have not been validated yet. The runtime depends on Home Assistant
Supervisor APIs and add-on behavior, so support outside HAOS should be treated
as experimental until explicitly tested.

## Names

| Item | Value |
|---|---|
| Project directory | repository root |
| Deploy directory | `/addons/alloy-logforwarder` |
| Home Assistant slug | `alloy_logforwarder` |
| Original project document | `homelab/docs/homeassistant/projects/alloy-logforwarder.md` |

## Development

Open this repository in VS Code:

```bash
code alloy-logforwarder
```

Then choose `Dev Containers: Reopen in Container`.

The devcontainer was successfully built and started headless on 2026-07-04
using the Dev Containers spec CLI. The remote workspace was:

```text
/workspaces/alloy-logforwarder
```

Local requirements:

| Requirement | Purpose |
|---|---|
| VS Code with Dev Containers extension | Open the app repository in a container |
| Docker Desktop or Docker Engine | Run devcontainers and app builds |
| Git | Source control |
| SSH to the target Home Assistant OS host | Deploy to `/addons/alloy-logforwarder` and refresh the store |

The devcontainer installs the base tooling for Home Assistant app development:

| Tool | Purpose |
|---|---|
| Docker CLI | Build the app image locally through the host Docker daemon |
| `shellcheck` | Validate shell scripts |
| `yamllint` | Validate Home Assistant YAML/config |
| `jq` | Inspect JSON options and API responses |
| `python3` with `yaml` module | Read app metadata from `config.yaml` |
| `rsync` | Prepare deploys to `/addons/alloy-logforwarder` |

The devcontainer also installs the VS Code extension `openai.chatgpt`, so
Codex/OpenAI assistance is available inside the container.

## Run Tasks

The repository contains VS Code tasks in `.vscode/tasks.json` and matching
scripts under `scripts/`.

| Task | Script | Purpose |
|---|---|---|
| `HA App: Check tools` | `scripts/check-tools.sh` | Checks local/devcontainer tooling |
| `HA App: Lint YAML` | `scripts/lint-yaml.sh` | Validates YAML files |
| `HA App: Lint shell` | `scripts/lint-shell.sh` | Validates shell scripts with ShellCheck |
| `HA App: Build image` | `scripts/build.sh` | Builds `alloy-logforwarder:dev` |
| `HA App: Smoke test` | `scripts/smoke-test.sh` | Starts the local image briefly for a smoke test |
| `HA App: Deploy dry-run` | `scripts/deploy.sh --dry-run` | Shows rsync changes to Home Assistant |
| `HA App: Deploy to Home Assistant` | `scripts/deploy.sh` | Deploys to `/addons/alloy-logforwarder` |
| `HA App: Refresh local store` | `scripts/refresh-store.sh` | Reloads the Home Assistant app store and checks local visibility |
| Production rollback dry-run | `scripts/rollback-production.sh --dry-run` | Shows rollback actions without changing production |
| Production rollback | `scripts/rollback-production.sh` | Stops the managed app and starts the unmanaged Alloy fallback container |

Build, smoke test and deploy require the minimal app skeleton (`Dockerfile`,
`config.yaml`, `run.sh`). Until that skeleton exists, these scripts intentionally
return a clear error.

Deploy and store refresh do not have a built-in Home Assistant target. Set the
target explicitly for your environment:

```bash
export HA_DEPLOY_TARGET=root@homeassistant.local:/addons/alloy-logforwarder/
export HA_SSH_TARGET=root@homeassistant.local

./scripts/deploy.sh --dry-run
./scripts/deploy.sh
./scripts/refresh-store.sh
```

`HA_DEPLOY_TARGET` must include the remote path. `HA_SSH_TARGET` is only the
SSH host used by Home Assistant CLI commands such as store refresh.

Production status:

- the app runs on Javastraat as `local_alloy_logforwarder`;
- the unmanaged container `mon-03-05-ha-alloy` remains active as fallback;
- the first production sources are `ha-core`, `zigbee2mqtt`, `mosquitto` and
  `alloy-logforwarder`.

Production rollback:

```bash
export HA_SSH_TARGET=root@homeassistant.local
export HA_APP_SLUG=local_alloy_logforwarder
export HA_UNMANAGED_ALLOY_CONTAINER=mon-03-05-ha-alloy

./scripts/rollback-production.sh --dry-run
./scripts/rollback-production.sh
```

The rollback stops the managed app and starts the unmanaged fallback container.
The app configuration is not removed. This script is intended for environments
that still have an unmanaged Alloy fallback container.

Last validated in the devcontainer on 2026-07-04:

```bash
./scripts/check-tools.sh
./scripts/lint-yaml.sh
./scripts/lint-shell.sh
./scripts/build.sh
./scripts/smoke-test.sh
```

Last validated against Home Assistant on 2026-07-04:

```bash
export HA_DEPLOY_TARGET=root@homeassistant.local:/addons/alloy-logforwarder/
export HA_SSH_TARGET=root@homeassistant.local

./scripts/deploy.sh --dry-run
./scripts/deploy.sh
./scripts/refresh-store.sh
```

Result: files are present under `/addons/alloy-logforwarder`, and Home
Assistant sees the local app with slug `alloy_logforwarder`.

## App Skeleton

| File | Purpose |
|---|---|
| `Dockerfile` | Builds on the Home Assistant base image and adds the Alloy binary plus `jq` |
| `config.yaml` | Home Assistant app metadata, options/schema and read-only config mount |
| `run.sh` | Reads options, renders Alloy config and starts the Alloy forwarding runtime |

The current `run.sh` implements basic log forwarding based on
`/data/options.json` and a dynamically rendered Alloy config. The runtime
creates the base config and can then append separate `.alloy` snippets for
additional HA apps/add-ons.

For Home Assistant Core logs, the preferred route is the Supervisor API
collector. The old standalone `source_path` and label options remain as a
fallback for real files. For HAOS/Supervised apps and add-ons, the preferred
route is `supervisor_log_sources`: the collector fetches logs through the
Supervisor API, and the selected `.alloy` snippet controls parsing, filtering
and mapping.

Default values:

| Option | Default |
|---|---|
| `loki_url` | `http://192.168.64.50:3310/loki/api/v1/push` |
| `source_path` | `/config/home-assistant.log` |
| `host_label` | `javastraat` |
| `site_label` | `javastraat` |
| `service_label` | `homeassistant` |
| `app_label` | `homeassistant` |
| `source_type_label` | `ha-core` |
| `environment_label` | `prod` |
| `stream_label` | `events` |
| `supervisor_core_logs_enabled` | `false` |
| `supervisor_core_logs_path` | `/tmp/alloy-logforwarder/homeassistant-core.log` |
| `supervisor_core_logs_poll_interval` | `30` |
| `supervisor_log_sources` | list of default disabled Supervisor sources |
| `custom_alloy_config_glob` | `/config/alloy-logforwarder/*.alloy` |

When `supervisor_core_logs_enabled=true`, the app periodically reads
`/core/logs` through the Supervisor API and writes unique lines to the temporary
spool file from `supervisor_core_logs_path`. Alloy tails that spool file and
pushes the lines to Loki. The token is read from `SUPERVISOR_TOKEN` or
`HASSIO_TOKEN`, including the s6 container environment file route used by Home
Assistant base images.

New configurations should preferably use `supervisor_log_sources`. This allows
the same collector to fetch multiple Supervisor log sources and use a dedicated
Alloy snippet per source:

```yaml
supervisor_log_sources:
  - enabled: true
    name: homeassistant_core
    slug: core
    endpoint: core/logs
    path: /tmp/alloy-logforwarder/homeassistant-core.log
    snippet: /etc/alloy-logforwarder/snippets/homeassistant-core.alloy
    service: homeassistant
    app: homeassistant
    source_type: ha-core
    stream: events

  - enabled: true
    name: zigbee2mqtt
    slug: 45df7312_zigbee2mqtt
    endpoint: addons/45df7312_zigbee2mqtt/logs
    path: /tmp/alloy-logforwarder/addons/45df7312_zigbee2mqtt.log
    snippet: /etc/alloy-logforwarder/snippets/zigbee2mqtt.alloy
    service: zigbee2mqtt
    app: zigbee2mqtt
    source_type: zigbee2mqtt
    stream: events
```

The collector defines where logs come from. The snippet defines how that app is
parsed, filtered and mapped to labels/payload fields.

App-specific snippets are not enabled automatically by default. Home Assistant
Core, Zigbee2MQTT and Mosquitto are shipped as standard snippets in the image.
They only become active when the matching source in `supervisor_log_sources` is
set to `enabled: true`. That is the recommended route for HAOS/Supervised,
because the collector fetches logs through the Supervisor API and the snippet
then controls parsing and mapping per app.

The Home Assistant Core snippet and the included Zigbee2MQTT and Mosquitto
examples are ports of the unmanaged MON-03 pipelines. They include noise
filters where applicable, severity normalization, app-specific field extraction
and `stage.pack` for payload fields. The snippets use placeholders such as
`__SOURCE_PATH__`, `__HOST_LABEL__` and `__SOURCE_TYPE_LABEL__`; `run.sh`
fills those per `supervisor_log_sources` item. Docker fields such as
`container_id` and `image` are not automatically available through this
Supervisor/API route.

Use the same route for Zigbee2MQTT and Mosquitto:

```yaml
supervisor_log_sources:
  - enabled: true
    name: mosquitto
    slug: core_mosquitto
    endpoint: addons/core_mosquitto/logs
    path: /tmp/alloy-logforwarder/addons/core_mosquitto.log
    snippet: /etc/alloy-logforwarder/snippets/mosquitto.alloy
    service: mosquitto
    app: mosquitto
    source_type: mosquitto
    stream: events
    poll_interval: 30
```

Configure an additional, still unknown HA app by placing your own `.alloy` file
that matches `custom_alloy_config_glob`, for example:

```text
/config/alloy-logforwarder/custom-app.alloy
```

Example snippet:

```alloy
loki.source.file "custom_app" {
  targets = [{
    __path__ = "/addon_configs/custom_app/app.log",
  }]
  forward_to = [loki.process.custom_app.receiver]
}

loki.process "custom_app" {
  stage.static_labels {
    values = {
      host        = "javastraat",
      site        = "javastraat",
      service     = "custom-app",
      app         = "custom-app",
      source_type = "ha-app",
      environment = "prod",
      stream      = "events",
      severity    = "info",
    }
  }

  forward_to = [loki.write.default.receiver]
}
```

Custom snippets must forward to `loki.write.default.receiver` themselves. That
writer is generated by the app.

Home Assistant shows more sources in the log page than just Core and add-ons,
for example Supervisor, Host, DNS, Audio and Multicast. Those sources can also
be configured through `supervisor_log_sources`. For built-in sources, `run.sh`
derives the correct Supervisor API route from `slug`; the `endpoint` field in
the defaults documents the route being used.

Included but disabled-by-default sources:

| Log page source | `endpoint` | `service`/`app`/`source_type` |
|---|---|---|
| Home Assistant Core | `core/logs` | `homeassistant` / `homeassistant` / `ha-core` |
| Supervisor | `supervisor/logs` | `supervisor` / `supervisor` / `supervisor` |
| Host | `host/logs` | `host` / `host` / `host` |
| DNS | `dns/logs` | `dns` / `dns` / `dns` |
| Audio | `audio/logs` | `audio` / `audio` / `audio` |
| Multicast | `multicast/logs` | `multicast` / `multicast` / `multicast` |
| Advanced SSH & Web Terminal | `addons/a0d7b954_ssh/logs` | `advanced-ssh` / `advanced-ssh` / `advanced-ssh` |
| Alloy Logforwarder | `addons/local_alloy_logforwarder/logs` | `alloy-logforwarder` / `alloy-logforwarder` / `alloy-logforwarder` |
| Mosquitto | `addons/core_mosquitto/logs` | `mosquitto` / `mosquitto` / `mosquitto` |
| Zigbee2MQTT | `addons/45df7312_zigbee2mqtt/logs` | `zigbee2mqtt` / `zigbee2mqtt` / `zigbee2mqtt` |

The system sources use the generic snippet
`/etc/alloy-logforwarder/snippets/supervisor-generic.alloy`. It follows the
same Grafana label convention as the app-specific snippets: `host`, `site`,
`service`, `app`, `source_type`, `environment`, `stream` and `severity`.

For unknown add-ons, the default route remains `addons/<slug>/logs`. For
unknown non-add-on Supervisor endpoints, the runtime must first be explicitly
extended or the `endpoint` field in Home Assistant options must be validated
reliably.

For access to Home Assistant config and add-on configs, the app uses:

```yaml
map:
  - type: homeassistant_config
    read_only: true
    path: /config
  - type: all_addon_configs
    read_only: true
    path: /addon_configs
```

## App Metadata

The required Home Assistant app metadata is stored in `config.yaml`.

| Field | Value |
|---|---|
| `name` | `Alloy Logforwarder` |
| `version` | `0.1.0` |
| `slug` | `alloy_logforwarder` |
| `description` | `Forward Home Assistant logs to the central Loki/Alloy logging stack.` |
| `arch` | `aarch64`, `amd64` |

Validation status:

| Check | Result |
|---|---|
| Required metadata | `name`, `version`, `slug`, `description` and `arch` are present |
| YAML lint | Passed |
| ShellCheck | Passed |
| Docker build | Passed for `alloy-logforwarder:dev` |
| Smoke test | Passed; container starts and writes startup log |
| Local app store visibility | Passed; slug `alloy_logforwarder` is visible after store reload |
