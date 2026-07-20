#!/usr/bin/env bash
# Build a classic “drag to Applications” DMG from PingMenuBar.app
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-}"
OUTPUT_DMG="${2:-${ROOT_DIR}/dist/PingMenuBar.dmg}"
VOLUME_NAME="PingMenuBar"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pingmenubar-dmg.XXXXXX")"
HELPER_SRC="${ROOT_DIR}/scripts/Open PingMenuBar.command"
HOWTO_SRC="${ROOT_DIR}/scripts/HOW-TO-OPEN.txt"
HELPER_NAME="Open PingMenuBar.command"
HOWTO_NAME="HOW-TO-OPEN.txt"

cleanup() {
  rm -rf "${STAGE_DIR}"
}
trap cleanup EXIT

if [[ -z "${APP_PATH}" || ! -d "${APP_PATH}" ]]; then
  echo "Usage: $0 /path/to/PingMenuBar.app [output.dmg]" >&2
  exit 1
fi

if [[ ! -f "${HELPER_SRC}" ]]; then
  echo "Missing first-open helper: ${HELPER_SRC}" >&2
  exit 1
fi

if [[ ! -f "${HOWTO_SRC}" ]]; then
  echo "Missing first-open notes: ${HOWTO_SRC}" >&2
  exit 1
fi

mkdir -p "$(dirname "${OUTPUT_DMG}")"
rm -f "${OUTPUT_DMG}"

# Stage app + first-open helper (unsigned builds hit Gatekeeper without this).
cp -R "${APP_PATH}" "${STAGE_DIR}/PingMenuBar.app"
cp "${HELPER_SRC}" "${STAGE_DIR}/${HELPER_NAME}"
cp "${HOWTO_SRC}" "${STAGE_DIR}/${HOWTO_NAME}"
chmod a+x "${STAGE_DIR}/${HELPER_NAME}"

if command -v create-dmg >/dev/null 2>&1; then
  # Layout:
  #   [App] ----→ [Applications]
  #   [Open helper]   [HOW-TO-OPEN]
  CREATE_DMG_ARGS=(
    --volname "${VOLUME_NAME}"
    --window-pos 200 120
    --window-size 660 460
    --icon-size 100
    --icon "PingMenuBar.app" 160 150
    --hide-extension "PingMenuBar.app"
    --app-drop-link 480 150
    --icon "${HELPER_NAME}" 160 340
    --hide-extension "${HELPER_NAME}"
    --icon "${HOWTO_NAME}" 480 340
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
