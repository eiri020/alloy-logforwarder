# Alloy Logforwarder

Forward selected Home Assistant logs to a Grafana Loki endpoint.

Alloy Logforwarder is a Home Assistant app for sending Home Assistant Core,
Supervisor, system and add-on logs to Loki with consistent labels such as
`host`, `site`, `service`, `app`, `source_type`, `environment`, `stream` and
`severity`.

Use it when Home Assistant already shows useful logs, but you also want to
search, filter, dashboard and alert on those logs in Grafana.

## Features

- Collects Home Assistant Core logs through the Supervisor API.
- Supports Supervisor, Host, DNS, Audio and Multicast logs.
- Supports add-on logs, including Mosquitto and Zigbee2MQTT presets.
- Allows custom `.alloy` snippets for additional add-ons.
- Forwards to an existing Loki endpoint.
- Keeps parsing and label mapping configurable per source.

## Requirements

- Home Assistant OS.
- A reachable Grafana Loki endpoint.
- Grafana or another Loki-compatible viewer for searching the logs.

This app has only been tested with Home Assistant OS. Other Home Assistant
installation types should be treated as experimental until validated.

## Documentation

- User documentation: [DOCS.md](DOCS.md)
- Developer documentation: [DEVELOPING.md](DEVELOPING.md)
- Changelog: add `CHANGELOG.md` before publishing releases.

## Screenshots

Screenshot placeholders and the required image checklist are documented in
[DOCS.md](DOCS.md#image-checklist).
