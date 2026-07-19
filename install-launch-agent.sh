#!/bin/bash
# Optional legacy helper: copy Release/Debug build to /Applications and install a LaunchAgent.
# Prefer the in-app "Open at Login" checkbox when using a copy from /Applications.

set -euo pipefail

APP_NAME="PingMenuBar.app"
DEST="/Applications/${APP_NAME}"

find_app() {
  # Prefer Release, then Debug, under DerivedData
  local found
  found=$(find "${HOME}/Library/Developer/Xcode/DerivedData" \
    -path "*/Build/Products/Release/${APP_NAME}" \
    -type d 2>/dev/null | head -1 || true)
  if [[ -n "${found}" ]]; then
    echo "${found}"
    return
  fi
  found=$(find "${HOME}/Library/Developer/Xcode/DerivedData" \
    -path "*/Build/Products/Debug/${APP_NAME}" \
    -type d 2>/dev/null | head -1 || true)
  if [[ -n "${found}" ]]; then
    echo "${found}"
    return
  fi
  return 1
}

APP_PATH="$(find_app || true)"
if [[ -z "${APP_PATH}" ]]; then
  echo "Error: ${APP_NAME} not found in DerivedData."
  echo "Build the app first in Xcode (Release preferred), then re-run."
  exit 1
fi

echo "Found app at: ${APP_PATH}"
echo "Copying to ${DEST}..."
# Prefer user-writable copy; fall back to sudo if needed
if cp -R "${APP_PATH}" "/Applications/" 2>/dev/null; then
  :
else
  sudo cp -R "${APP_PATH}" "/Applications/"
fi

PLIST_PATH="${HOME}/Library/LaunchAgents/com.example.PingMenuBar.plist"
echo "Creating launch agent at: ${PLIST_PATH}"

cat > "${PLIST_PATH}" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.example.PingMenuBar</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/PingMenuBar.app/Contents/MacOS/PingMenuBar</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
EOF

echo "Loading launch agent..."
launchctl unload "${PLIST_PATH}" 2>/dev/null || true
launchctl load "${PLIST_PATH}"

echo ""
echo "PingMenuBar installed."
echo "Tip: Prefer the in-app Open at Login checkbox instead of this LaunchAgent when possible."
echo ""
echo "To uninstall the LaunchAgent:"
echo "  launchctl unload ${PLIST_PATH}"
echo "  rm ${PLIST_PATH}"
