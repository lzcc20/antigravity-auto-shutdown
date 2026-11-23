#!/usr/bin/env sh
set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
DEST="${HOME}/.gemini/config/plugins/auto-shutdown"

echo "[Auto Shutdown] Installing Antigravity plugin..."
echo "  Source: ${SRC}"
echo "  Target: ${DEST}"

mkdir -p "${HOME}/.gemini/config/plugins"
rm -rf "${DEST}"
mkdir -p "${DEST}"

cp "${SRC}/plugin.json" "${DEST}/plugin.json"
cp "${SRC}/hooks.json" "${DEST}/hooks.json"
cp "${SRC}/mcp_config.json" "${DEST}/mcp_config.json"
cp "${SRC}/README.md" "${DEST}/README.md"
cp "${SRC}/LICENSE" "${DEST}/LICENSE"
cp "${SRC}/THIRD-PARTY-NOTICES.md" "${DEST}/THIRD-PARTY-NOTICES.md"
cp -R "${SRC}/assets" "${DEST}/assets"
cp -R "${SRC}/scripts" "${DEST}/scripts"
cp -R "${SRC}/skills" "${DEST}/skills"
cp -R "${SRC}/ui" "${DEST}/ui"

chmod +x "${DEST}/scripts/"*.mjs 2>/dev/null || true

echo ""
echo "[Auto Shutdown] Installed successfully!"
echo "  - Native UI is now available in Antigravity:"
echo "      * Left Sidebar -> Plugins -> Auto Shutdown (Full Page)"
echo "      * Side Panel '+' menu -> Auto Shutdown"
echo "      * Chat -> /auto-shutdown"
echo "  - Config & state are preserved at: ${HOME}/.gemini/config/auto-shutdown"
