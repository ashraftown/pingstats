#!/usr/bin/env bash
# Install / first-open helper for unsigned PingMenuBar builds.
#
# IMPORTANT: Do NOT double-click this file in Finder.
# On modern macOS, Gatekeeper blocks unsigned downloads the same way as apps
# when launched from Finder. Run it from Terminal instead:
#
#   bash "/Volumes/PingMenuBar/install.sh"
#
# Or drag this file into a Terminal window and press Return.
# Or (after copying the app to Applications):
#
#   xattr -cr /Applications/PingMenuBar.app && open /Applications/PingMenuBar.app
#
set -euo pipefail

APP_NAME="PingMenuBar.app"
DEST="/Applications/${APP_NAME}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="${SCRIPT_DIR}/${APP_NAME}"

echo "PingMenuBar — install / first open"
echo "================================="
echo

# Prefer the copy already in Applications; otherwise install from this volume.
if [[ -d "${DEST}" ]]; then
  echo "Found ${DEST}"
elif [[ -d "${SOURCE}" ]]; then
  echo "Copying ${APP_NAME} → /Applications …"
  ditto "${SOURCE}" "${DEST}"
else
  echo "error: ${APP_NAME} not found in /Applications or next to this script." >&2
  echo >&2
  echo "Drag PingMenuBar to Applications, then run:" >&2
  echo "  xattr -cr /Applications/PingMenuBar.app && open /Applications/PingMenuBar.app" >&2
  exit 1
fi

echo "Clearing macOS quarantine (unsigned release)…"
xattr -dr com.apple.quarantine "${DEST}" 2>/dev/null || true
xattr -cr "${DEST}" 2>/dev/null || true

if xattr -p com.apple.quarantine "${DEST}" >/dev/null 2>&1; then
  echo "warning: quarantine attribute may still be present." >&2
  echo "Try System Settings → Privacy & Security → Open Anyway." >&2
fi

echo "Launching…"
open "${DEST}"

echo
echo "Done. PingMenuBar should appear in the menu bar."
echo "Later opens: use Applications / Spotlight as usual."
