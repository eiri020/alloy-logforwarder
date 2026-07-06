# Codex Instructions

This repository contains the standalone Alloy Logforwarder Home Assistant app.
For homelab work it still follows the same documentation and engineering style as the original homelab workspace.

- Primary app documentation: `README.md`
- Runtime metadata: `config.yaml`
- Original homelab project documentation: `/workspaces/homelab/docs/homeassistant/projects/alloy-logforwarder.md`

When changing this app, follow the inherited homelab rules:

- Treat documentation as first-class code.
- Update relevant documentation in the same change as functional updates.
- Prefer simplicity, maintainability, security, repeatability, automation, and
  observability.
- Avoid duplicated configuration and multiple sources of truth.

App-specific context:

- App source root: repository root
- Home Assistant deploy target: `/addons/alloy-logforwarder`
- Home Assistant slug: `alloy_logforwarder`
- Project documentation: `README.md`, with broader homelab history in the original homelab project documentation

Use the app scripts as the standard workflow:

- `./scripts/check-tools.sh`
- `./scripts/lint-yaml.sh`
- `./scripts/lint-shell.sh`
- `./scripts/build.sh`
- `./scripts/smoke-test.sh`
- `./scripts/deploy.sh --dry-run`

Keep `Dockerfile`, `config.yaml`, `run.sh`, snippets and scripts valid together. Update documentation in the same change as functional updates.
