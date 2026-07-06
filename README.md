# Alloy Logforwarder

Home Assistant app voor het forwarden van Home Assistant logs naar de centrale
Loki/Alloy loggingstack.

## Status

Status: functionele runtime aanwezig. De app kan Home Assistant Core logs via
de Supervisor API lezen en configureerbare HA app/add-on logbronnen via losse
`.alloy` snippets forwarden naar Loki.

Voor HAOS/Supervised is de Supervisor API-route de voorkeursroute voor Home
Assistant Core logs. `home-assistant.log` wordt daar niet langer als
betrouwbare bron gebruikt.

## Namen

| Onderdeel | Waarde |
|---|---|
| Projectdirectory | repository root |
| Deploy-directory | `/addons/alloy-logforwarder` |
| Home Assistant slug | `alloy_logforwarder` |
| Oorspronkelijk projectdocument | `homelab/docs/homeassistant/projects/alloy-logforwarder.md` |

## Development

Open deze repository in VS Code:

```bash
code alloy-logforwarder
```

Kies daarna `Dev Containers: Reopen in Container`.

De devcontainer is op 2026-07-04 succesvol headless gebouwd en gestart via de
Dev Containers spec CLI. De remote workspace was:

```text
/workspaces/alloy-logforwarder
```

Lokale vereisten:

| Vereiste | Doel |
|---|---|
| VS Code met Dev Containers extension | App-map openen in container |
| Docker Desktop of Docker Engine | Devcontainer en app-builds draaien |
| Git | Broncode beheren |
| SSH naar `root@192.168.64.10` | Deploy naar `/addons/alloy-logforwarder` en store refresh |

De devcontainer installeert de basistooling voor Home Assistant app
development:

| Tool | Doel |
|---|---|
| Docker CLI | App image lokaal bouwen via de host Docker daemon |
| `shellcheck` | Shellscripts valideren |
| `yamllint` | Home Assistant YAML/config valideren |
| `jq` | JSON opties en API responses inspecteren |
| `python3` met `yaml` module | App metadata uit `config.yaml` lezen |
| `rsync` | Deploy naar `/addons/alloy-logforwarder` voorbereiden |

De devcontainer installeert ook de VS Code extension `openai.chatgpt`, zodat
Codex/OpenAI ondersteuning beschikbaar is binnen de container.

## Run Taken

De app-map bevat VS Code tasks in `.vscode/tasks.json` en bijbehorende scripts
onder `scripts/`.

| Task | Script | Doel |
|---|---|---|
| `HA App: Check tools` | `scripts/check-tools.sh` | Controleert lokale/devcontainer tooling |
| `HA App: Lint YAML` | `scripts/lint-yaml.sh` | Valideert YAML-bestanden |
| `HA App: Lint shell` | `scripts/lint-shell.sh` | Valideert shellscripts met ShellCheck |
| `HA App: Build image` | `scripts/build.sh` | Bouwt `alloy-logforwarder:dev` |
| `HA App: Smoke test` | `scripts/smoke-test.sh` | Start de lokale image kort voor een smoke test |
| `HA App: Deploy dry-run` | `scripts/deploy.sh --dry-run` | Toont rsync-wijzigingen naar Home Assistant |
| `HA App: Deploy to Home Assistant` | `scripts/deploy.sh` | Deployed naar `/addons/alloy-logforwarder` |
| `HA App: Refresh local store` | `scripts/refresh-store.sh` | Herlaadt de Home Assistant app store en controleert lokale zichtbaarheid |
| Productie rollback dry-run | `scripts/rollback-production.sh --dry-run` | Toont rollbackacties zonder productie te wijzigen |
| Productie rollback | `scripts/rollback-production.sh` | Stopt managed app en start unmanaged Alloy fallbackcontainer |

Build, smoke test en deploy vereisen de minimale app skeleton
(`Dockerfile`, `config.yaml`, `run.sh`). Tot die skeleton bestaat geven deze
scripts bewust een duidelijke foutmelding.

De standaard deploy-target gebruikt het Home Assistant IP-adres:

```text
root@192.168.64.10:/addons/alloy-logforwarder/
```

Gebruik `HA_DEPLOY_TARGET` om dit tijdelijk te overschrijven.
Gebruik `HA_SSH_TARGET` om de SSH-host voor store refresh tijdelijk te
overschrijven.

Productiestatus:

- de app draait op Javastraat als `local_alloy_logforwarder`;
- de unmanaged container `mon-03-05-ha-alloy` blijft actief als fallback;
- de eerste productiebronnen zijn `ha-core`, `zigbee2mqtt`, `mosquitto` en
  `alloy-logforwarder`.

Productierollback:

```bash
./scripts/rollback-production.sh --dry-run
./scripts/rollback-production.sh
```

De rollback stopt de managed app en start de unmanaged fallbackcontainer. De
appconfig wordt niet verwijderd.

Laatst gevalideerd in de devcontainer op 2026-07-04:

```bash
./scripts/check-tools.sh
./scripts/lint-yaml.sh
./scripts/lint-shell.sh
./scripts/build.sh
./scripts/smoke-test.sh
```

Laatst gevalideerd tegen Home Assistant op 2026-07-04:

```bash
./scripts/deploy.sh --dry-run
./scripts/deploy.sh
./scripts/refresh-store.sh
```

Resultaat: bestanden staan onder `/addons/alloy-logforwarder` en Home
Assistant ziet de lokale app met slug `alloy_logforwarder`.

## App Skeleton

| Bestand | Doel |
|---|---|
| `Dockerfile` | Bouwt op Home Assistant base image en voegt Alloy binary + `jq` toe |
| `config.yaml` | Home Assistant app metadata, opties/schema en read-only config mount |
| `run.sh` | Leest opties, rendert Alloy-config en start Alloy forwarding runtime |

De huidige `run.sh` implementeert basislogforwarding op basis van
`/data/options.json` en een dynamisch gerenderde Alloy-config. De runtime maakt
de basisconfig en kan daarna losse `.alloy` snippets appenden voor extra HA
apps/add-ons.

Voor Home Assistant Core logs is de voorkeursroute de Supervisor API collector.
De oude losse `source_path` en labelopties blijven als fallback bestaan voor
echte bestanden. Voor HAOS/Supervised apps en add-ons is de voorkeursroute
`supervisor_log_sources`: de collector haalt logs op via de Supervisor API en
de gekozen `.alloy` snippet bepaalt parsing, filtering en mapping.

Standaardwaarden:

| Optie | Standaard |
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
| `supervisor_log_sources` | lijst met standaard uitgeschakelde Supervisor-bronnen |
| `custom_alloy_config_glob` | `/config/alloy-logforwarder/*.alloy` |

Wanneer `supervisor_core_logs_enabled=true` leest de app periodiek
`/core/logs` via de Supervisor API en schrijft unieke regels naar de tijdelijke
spool-file uit `supervisor_core_logs_path`. Alloy leest die spool-file en pusht
de regels naar Loki. De token wordt gelezen uit `SUPERVISOR_TOKEN` of
`HASSIO_TOKEN`, inclusief de s6 container environment file-route die Home
Assistant base images gebruiken.

Nieuwe configuraties gebruiken bij voorkeur `supervisor_log_sources`. Daarmee
kan dezelfde collector meerdere Supervisor-logbronnen ophalen en per bron een
eigen Alloy snippet gebruiken:

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

De collector bepaalt hiermee waar logs vandaan komen. De snippet bepaalt hoe
die app wordt geparsed, gefilterd en gemapt naar labels/payloadvelden.

Standaard worden geen app-specifieke snippets automatisch geactiveerd.
Home Assistant core, Zigbee2MQTT en Mosquitto worden als standaard-snippets
meegeleverd in de image. Ze worden pas actief wanneer je de bijbehorende
bron in `supervisor_log_sources` op `enabled: true` zet. Dat is de aanbevolen
route voor HAOS/Supervised, omdat de collector de logs via de Supervisor API
ophaalt en de snippet daarna per app de parsing en mapping bepaalt.

De Home Assistant core snippet en de meegeleverde Zigbee2MQTT- en
Mosquitto-voorbeelden zijn ports van de unmanaged MON-03 pipelines. Ze bevatten
ruisfilters waar van toepassing, severity-normalisatie, app-specifieke
veldextractie en `stage.pack` voor payloadvelden. De snippets gebruiken
placeholders zoals `__SOURCE_PATH__`, `__HOST_LABEL__` en
`__SOURCE_TYPE_LABEL__`; `run.sh` vult die in per `supervisor_log_sources`
item. Dockervelden zoals `container_id` en `image` zijn in deze Supervisor/API
route niet automatisch beschikbaar.

Voor Zigbee2MQTT en Mosquitto gebruik je dezelfde route:

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

Een extra, nog onbekende HA app configureer je door zelf een `.alloy` bestand
te plaatsen dat matcht met `custom_alloy_config_glob`, bijvoorbeeld:

```text
/config/alloy-logforwarder/custom-app.alloy
```

Voorbeeld van zo'n snippet:

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

Custom snippets moeten zelf naar `loki.write.default.receiver` forwarden. Die
writer wordt door de app gegenereerd.

Home Assistant toont in de logpagina meer bronnen dan alleen Core en add-ons,
bijvoorbeeld Supervisor, Host, DNS, Audio en Multicast. Ook die bronnen kunnen
via `supervisor_log_sources` worden geconfigureerd. Voor de ingebouwde bronnen
leidt `run.sh` de juiste Supervisor API-route af uit `slug`; het `endpoint`
veld in de defaults documenteert de gebruikte route.

Meegeleverde maar standaard uitgeschakelde bronnen:

| Logpagina-bron | `endpoint` | `service`/`app`/`source_type` |
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

De systeembronnen gebruiken de generieke snippet
`/etc/alloy-logforwarder/snippets/supervisor-generic.alloy`. Die houdt dezelfde
Grafana-labelconventie aan als de app-specifieke snippets:
`host`, `site`, `service`, `app`, `source_type`, `environment`, `stream` en
`severity`.

Voor onbekende add-ons blijft de standaardroute
`addons/<slug>/logs`. Voor onbekende niet-add-on Supervisor endpoints moet de
runtime eerst expliciet worden uitgebreid of moet het `endpoint` veld in de
Home Assistant opties betrouwbaar worden gevalideerd.

Voor toegang tot Home Assistant config en add-on configuraties gebruikt de app:

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

De verplichte Home Assistant app metadata staat in `config.yaml`.

| Veld | Waarde |
|---|---|
| `name` | `Alloy Logforwarder` |
| `version` | `0.1.0` |
| `slug` | `alloy_logforwarder` |
| `description` | `Forward Home Assistant logs to the central Loki/Alloy logging stack.` |
| `arch` | `aarch64`, `amd64` |

Validatiestatus:

| Controle | Resultaat |
|---|---|
| Verplichte metadata | `name`, `version`, `slug`, `description` en `arch` aanwezig |
| YAML lint | Geslaagd |
| ShellCheck | Geslaagd |
| Docker build | Geslaagd voor `alloy-logforwarder:dev` |
| Smoke test | Geslaagd; container start en schrijft startup-log |
| Lokale app store zichtbaarheid | Geslaagd; slug `alloy_logforwarder` zichtbaar na store reload |
