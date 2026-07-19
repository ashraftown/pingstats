#!/usr/bin/env bash
# Build a classic “drag to Applications” DMG from PingMenuBar.app
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-}"
OUTPUT_DMG="${2:-${ROOT_DIR}/dist/PingMenuBar.dmg}"
VOLUME_NAME="PingMenuBar"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pingmenubar-dmg.XXXXXX")"

cleanup() {
  rm -rf "${STAGE_DIR}"
}
trap cleanup EXIT

if [[ -z "${APP_PATH}" || ! -d "${APP_PATH}" ]]; then
  echo "Usage: $0 /path/to/PingMenuBar.app [output.dmg]" >&2
  exit 1
fi

mkdir -p "$(dirname "${OUTPUT_DMG}")"
rm -f "${OUTPUT_DMG}"

# Stage install layout: app + Applications shortcut
cp -R "${APP_PATH}" "${STAGE_DIR}/PingMenuBar.app"
ln -s /Applications "${STAGE_DIR}/Applications"

if command -v create-dmg >/dev/null 2>&1; then
  # Pretty Finder window: app on the left, Applications on the right
  create-dmg \
    --volname "${VOLUME_NAME}" \
    --volicon "${STAGE_DIR}/PingMenuBar.app/Contents/Resources/AppIcon.icns" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 100 \
    --icon "PingMenuBar.app" 160 180 \
    --hide-extension "PingMenuBar.app" \
    --app-drop-link 480 180 \
    --no-internet-enable \
    "${OUTPUT_DMG}" \
    "${STAGE_DIR}" || {
      # create-dmg exits non-zero if the volume icon is missing; retry without it
      create-dmg \
        --volname "${VOLUME_NAME}" \
        --window-pos 200 120 \
        --window-size 660 400 \
        --icon-size 100 \
        --icon "PingMenuBar.app" 160 180 \
        --hide-extension "PingMenuBar.app" \
        --app-drop-link 480 180 \
        --no-internet-enable \
        "${OUTPUT_DMG}" \
        "${STAGE_DIR}"
    }
else
  echo "create-dmg not found; using hdiutil fallback (no custom window layout)" >&2
  hdiutil create \
    -volname "${VOLUME_NAME}" \
    -srcfolder "${STAGE_DIR}" \
    -ov \
    -format UDZO \
    "${OUTPUT_DMG}"
fi

echo "Created ${OUTPUT_DMG}"
ls -lh "${OUTPUT_DMG}"
