#!/usr/bin/env bash
# Build a classic “drag to Applications” DMG from PingStats.app
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-}"
OUTPUT_DMG="${2:-${ROOT_DIR}/dist/PingStats.dmg}"
VOLUME_NAME="PingStats"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pingstats-dmg.XXXXXX")"
HOWTO_SRC="${ROOT_DIR}/scripts/How to Open.html"
HOWTO_NAME="How to Open.html"
BACKGROUND_SRC="${ROOT_DIR}/assets/dmg-background.png"

# Must match assets/dmg-background.png pixel size at 72 DPI (create-dmg convention:
# window points == background pixels). Keep window origin near (0,0) so CI/virtual
# displays can realize the full size when Finder writes .DS_Store.
WIN_W=700
WIN_H=540

cleanup() {
  rm -rf "${STAGE_DIR}"
}
trap cleanup EXIT

if [[ -z "${APP_PATH}" || ! -d "${APP_PATH}" ]]; then
  echo "Usage: $0 /path/to/PingStats.app [output.dmg]" >&2
  exit 1
fi

if [[ ! -f "${HOWTO_SRC}" ]]; then
  echo "Missing first-open guide: ${HOWTO_SRC}" >&2
  exit 1
fi

if [[ ! -f "${BACKGROUND_SRC}" ]]; then
  echo "Missing DMG background: ${BACKGROUND_SRC}" >&2
  exit 1
fi

# Guardrail: background pixel size should match --window-size (72 DPI).
if command -v sips >/dev/null 2>&1; then
  # Normalize DPI on macOS runners (Finder uses this for point size).
  sips -s dpiWidth 72 -s dpiHeight 72 "${BACKGROUND_SRC}" >/dev/null
  BG_W="$(sips -g pixelWidth "${BACKGROUND_SRC}" 2>/dev/null | awk '/pixelWidth/ {print $2}')"
  BG_H="$(sips -g pixelHeight "${BACKGROUND_SRC}" 2>/dev/null | awk '/pixelHeight/ {print $2}')"
  if [[ -n "${BG_W}" && -n "${BG_H}" ]]; then
    if [[ "${BG_W}" -ne "${WIN_W}" || "${BG_H}" -ne "${WIN_H}" ]]; then
      echo "error: background is ${BG_W}×${BG_H} but window is ${WIN_W}×${WIN_H}" >&2
      echo "They must match (create-dmg: points == pixels at 72 DPI)." >&2
      exit 1
    fi
  fi
elif command -v python3 >/dev/null 2>&1; then
  python3 - "${BACKGROUND_SRC}" "${WIN_W}" "${WIN_H}" <<'PY'
import sys
from PIL import Image
path, ww, wh = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
im = Image.open(path)
if im.size != (ww, wh):
    sys.exit(f"error: background is {im.size[0]}×{im.size[1]} but window is {ww}×{wh}")
# Ensure 72 DPI metadata is present for Finder
if im.info.get("dpi") != (72, 72) and im.info.get("dpi") != (72.0, 72.0):
    im.save(path, "PNG", dpi=(72, 72), optimize=True)
    print(f"Normalized DPI to 72 on {path}")
PY
fi

mkdir -p "$(dirname "${OUTPUT_DMG}")"
rm -f "${OUTPUT_DMG}"

# Stage app + simple first-open guide (no scripts — Gatekeeper blocks those too).
cp -R "${APP_PATH}" "${STAGE_DIR}/PingStats.app"
cp "${HOWTO_SRC}" "${STAGE_DIR}/${HOWTO_NAME}"

if command -v create-dmg >/dev/null 2>&1; then
  # Layout (700×540 points / pixels):
  #   [App] ----→ [Applications]
  #        [How to Open]
  # window-pos is near the top-left so small CI screens can fit the full bounds
  # when AppleScript writes .DS_Store (a large pos+size can get clamped).
  CREATE_DMG_ARGS=(
    --volname "${VOLUME_NAME}"
    --window-pos 50 50
    --window-size "${WIN_W}" "${WIN_H}"
    --icon-size 96
    --text-size 12
    --icon "PingStats.app" 170 200
    --hide-extension "PingStats.app"
    --app-drop-link 530 200
    --icon "${HOWTO_NAME}" 350 420
    --hide-extension "${HOWTO_NAME}"
    --background "${BACKGROUND_SRC}"
    --no-internet-enable
  )

  ICNS="${STAGE_DIR}/PingStats.app/Contents/Resources/AppIcon.icns"
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

echo "Created ${OUTPUT_DMG} (window ${WIN_W}×${WIN_H}, background matched @ 72 DPI)"
ls -lh "${OUTPUT_DMG}"
