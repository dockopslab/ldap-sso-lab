#!/bin/sh
set -euo pipefail

ORIGINAL_ENTRYPOINT="/app/docker/entrypoint.sh"
CUSTOM_CA_SOURCE="/certs/ca.crt"
CUSTOM_CA_TARGET_DIR="/usr/local/share/ca-certificates"
CUSTOM_CA_TARGET="${CUSTOM_CA_TARGET_DIR}/pocket-id-ca.crt"

if [ -f "$CUSTOM_CA_SOURCE" ]; then
  mkdir -p "$CUSTOM_CA_TARGET_DIR"
  # Alpine's update-ca-certificates expects .crt files beneath /usr/local/share/ca-certificates
  cp "$CUSTOM_CA_SOURCE" "$CUSTOM_CA_TARGET"
  update-ca-certificates >/dev/null 2>&1 || true
fi

exec "$ORIGINAL_ENTRYPOINT" "$@"
