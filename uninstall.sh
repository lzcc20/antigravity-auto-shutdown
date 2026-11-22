#!/usr/bin/env sh
set -eu

DEST="${HOME}/.gemini/config/plugins/auto-shutdown"

echo "[Auto Shutdown] Uninstalling Antigravity plugin..."

if [ -f "${DEST}/scripts/ctl.mjs" ]; then
  node "${DEST}/scripts/ctl.mjs" disarm >/dev/null 2>&1 || true
fi

if [ -d "${DEST}" ]; then
  rm -rf "${DEST}"
  echo "[Auto Shutdown] Removed plugin directory: ${DEST}"
else
  echo "[Auto Shutdown] Plugin directory not found: ${DEST}"
fi

echo "[Auto Shutdown] User preferences at ${HOME}/.gemini/config/auto-shutdown were preserved."
