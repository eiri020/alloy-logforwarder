#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

image_name="${IMAGE_NAME:-alloy-logforwarder:dev}"

if [ ! -f Dockerfile ]; then
  echo "Dockerfile is missing. Add the app skeleton before building." >&2
  exit 2
fi

docker build -t "$image_name" .
