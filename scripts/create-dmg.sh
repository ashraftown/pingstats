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

# Stage only the app. create-dmg --app-drop-link adds the Applications shortcut.
cp -R "${APP_PATH}" "${STAGE_DIR}/PingMenuBar.app"

if command -v create-dmg >/dev/null 2>&1; then
  CREATE_DMG_ARGS=(
    --volname "${VOLUME_NAME}"
    --window-pos 200 120
    --window-size 660 400
    --icon-size 100
    --icon "PingMenuBar.app" 160 180
    --hide-extension "PingMenuBar.app"
    --app-drop-link 480 180
    --no-internet-enable
  )

  # Custom Finder background with “Click & Drag to Install” guidance
  BACKGROUND="${ROOT_DIR}/assets/dmg-background.png"
  if [[ -f "${BACKGROUND}" ]]; then
    CREATE_DMG_ARGS+=(--background "${BACKGROUND}")
  else
    echo "Warning: DMG background not found at ${BACKGROUND}" >&2
  fi

  # Optional volume icon only if the built app actually embeds one
  ICNS="${STAGE_DIR}/PingMenuBar.app/Contents/Resources/AppIcon.icns"
  if [[ -f "${ICNS}" ]]; then
    CREATE_DMG_ARGS+=(--volicon "${ICNS}")
  fi

  create-dmg "${CREATE_DMG_ARGS[@]}" "${OUTPUT_DMG}" "${STAGE_DIR}"
else
  echo "create-dmg not found; using hdiutil fallback (no custom window layout)" >&2
  ln -s /Applications "${STAGE_DIR}/Applications"
  hdiutil create \
    -volname "${VOLUME_NAME}" \
    -srcfolder "${STAGE_DIR}" \
    -ov \
    -format UDZO \
    "${OUTPUT_DMG}"
fi

echo "Created ${OUTPUT_DMG}"
ls -lh "${OUTPUT_DMG}"
