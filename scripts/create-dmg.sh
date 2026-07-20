#!/usr/bin/env bash
# Build a classic “drag to Applications” DMG from PingMenuBar.app
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-}"
OUTPUT_DMG="${2:-${ROOT_DIR}/dist/PingMenuBar.dmg}"
VOLUME_NAME="PingMenuBar"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pingmenubar-dmg.XXXXXX")"

# Staged helpers (unsigned builds cannot rely on double-click; see START HERE.txt)
START_SRC="${ROOT_DIR}/scripts/START HERE.txt"
INSTALL_SRC="${ROOT_DIR}/scripts/install.sh"
WEBLOC_SRC="${ROOT_DIR}/scripts/Privacy & Security.webloc"
START_NAME="START HERE.txt"
INSTALL_NAME="install.sh"
WEBLOC_NAME="Privacy & Security.webloc"

cleanup() {
  rm -rf "${STAGE_DIR}"
}
trap cleanup EXIT

if [[ -z "${APP_PATH}" || ! -d "${APP_PATH}" ]]; then
  echo "Usage: $0 /path/to/PingMenuBar.app [output.dmg]" >&2
  exit 1
fi

for required in "${START_SRC}" "${INSTALL_SRC}" "${WEBLOC_SRC}"; do
  if [[ ! -f "${required}" ]]; then
    echo "Missing DMG helper file: ${required}" >&2
    exit 1
  fi
done

mkdir -p "$(dirname "${OUTPUT_DMG}")"
rm -f "${OUTPUT_DMG}"

# Stage app + first-open docs/helpers.
cp -R "${APP_PATH}" "${STAGE_DIR}/PingMenuBar.app"
cp "${START_SRC}" "${STAGE_DIR}/${START_NAME}"
cp "${INSTALL_SRC}" "${STAGE_DIR}/${INSTALL_NAME}"
cp "${WEBLOC_SRC}" "${STAGE_DIR}/${WEBLOC_NAME}"
chmod a+x "${STAGE_DIR}/${INSTALL_NAME}"

# Remove obsolete helper name if present from older packaging experiments
rm -f "${STAGE_DIR}/Open PingMenuBar.command" "${STAGE_DIR}/HOW-TO-OPEN.txt"

if command -v create-dmg >/dev/null 2>&1; then
  # Layout:
  #   [App] ------------→ [Applications]
  #   [START HERE]   [install.sh]   [Privacy]
  CREATE_DMG_ARGS=(
    --volname "${VOLUME_NAME}"
    --window-pos 200 100
    --window-size 700 480
    --icon-size 88
    --icon "PingMenuBar.app" 140 140
    --hide-extension "PingMenuBar.app"
    --app-drop-link 520 140
    --icon "${START_NAME}" 140 340
    --icon "${INSTALL_NAME}" 330 340
    --icon "${WEBLOC_NAME}" 520 340
    --no-internet-enable
  )

  BACKGROUND="${ROOT_DIR}/assets/dmg-background.png"
  if [[ -f "${BACKGROUND}" ]]; then
    CREATE_DMG_ARGS+=(--background "${BACKGROUND}")
  else
    echo "Warning: DMG background not found at ${BACKGROUND}" >&2
  fi

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
