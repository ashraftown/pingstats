#!/usr/bin/env bash
# First-launch helper for unsigned PingMenuBar release builds.
#
# Downloads from the internet are marked with macOS quarantine. Unsigned apps
# then hit Gatekeeper (“Apple could not verify…”) and never start — so the app
# itself cannot show guidance. This helper runs outside the app bundle:
#   1. Ensures PingMenuBar is in /Applications (copies from the DMG if needed)
#   2. Clears the quarantine attribute
#   3. Launches the app
#
# Double-click this file after opening the DMG (Terminal will open briefly).
set -euo pipefail

APP_NAME="PingMenuBar.app"
DEST="/Applications/${APP_NAME}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="${SCRIPT_DIR}/${APP_NAME}"

die() {
  local msg="$1"
  echo "error: ${msg}" >&2
  if command -v osascript >/dev/null 2>&1; then
    # Keep the GUI string single-line; full detail is printed above in Terminal.
    local short
    short="$(printf '%s' "${msg}" | tr '\n' ' ' | sed 's/"//g' | cut -c1-240)"
    osascript -e "display dialog \"${short}\" buttons {\"OK\"} default button 1 with icon stop with title \"PingMenuBar\"" >/dev/null 2>&1 || true
  fi
  exit 1
}

echo "PingMenuBar — first open helper"
echo

# Prefer the copy already in Applications; otherwise install from this volume.
if [[ -d "${DEST}" ]]; then
  echo "Found ${DEST}"
elif [[ -d "${SOURCE}" ]]; then
  echo "Copying ${APP_NAME} to /Applications…"
  ditto "${SOURCE}" "${DEST}"
else
  die "PingMenuBar.app was not found.

Drag PingMenuBar to Applications first, then run this helper again.

Or paste this into Terminal:
  xattr -cr /Applications/PingMenuBar.app && open /Applications/PingMenuBar.app"
fi

echo "Clearing macOS quarantine (unsigned release builds)…"
# Targeted first; full clear is a reliable fallback on nested bundles.
xattr -dr com.apple.quarantine "${DEST}" 2>/dev/null || true
xattr -cr "${DEST}" 2>/dev/null || true

echo "Launching…"
open "${DEST}"

echo
echo "Done. PingMenuBar should appear in the menu bar."
echo "You can close this Terminal window."
echo
# Keep the window readable when double-clicked; user closes when ready.
read -r -p "Press Return to close…" _ || true
