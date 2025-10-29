#!/bin/bash

# Script to install PingMenuBar as a launch agent

# Find the built app
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/PingMenuBar-*/Build/Products/Debug/PingMenuBar.app -maxdepth 0 2>/dev/null | head -1)

if [ -z "$APP_PATH" ]; then
    echo "Error: PingMenuBar.app not found. Please build the app first (Cmd+B in Xcode)."
    exit 1
fi

echo "Found app at: $APP_PATH"

# Copy to Applications folder
echo "Copying to /Applications..."
sudo cp -R "$APP_PATH" /Applications/

# Create LaunchAgent plist
PLIST_PATH="$HOME/Library/LaunchAgents/com.example.PingMenuBar.plist"

echo "Creating launch agent at: $PLIST_PATH"

cat > "$PLIST_PATH" << 'EOF'
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

# Load the launch agent
echo "Loading launch agent..."
launchctl load "$PLIST_PATH"

echo ""
echo "✅ PingMenuBar installed successfully!"
echo "The app will now launch automatically on startup."
echo ""
echo "To uninstall, run:"
echo "  launchctl unload $PLIST_PATH"
echo "  rm $PLIST_PATH"
