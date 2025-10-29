# Installing PingMenuBar to Launch on Startup

## Quick Method (Recommended)

1. **Build the app** in Xcode (press Cmd+B)

2. **Run the install script**:
   ```bash
   ./install-launch-agent.sh
   ```

This will:
- Copy the app to /Applications
- Create a launch agent to start it automatically on login
- Launch the app immediately

## Manual Method

1. **Build the app** in Xcode (Cmd+B)

2. **Find the built app**:
   ```bash
   open ~/Library/Developer/Xcode/DerivedData/PingMenuBar-*/Build/Products/Debug/
   ```

3. **Copy to Applications**:
   - Drag `PingMenuBar.app` to your Applications folder

4. **Add to Login Items**:
   - Open **System Settings**
   - Go to **General → Login Items**
   - Click the **+** button
   - Select **PingMenuBar** from Applications
   - Done!

## Uninstalling Auto-Launch

If you used the script:
```bash
launchctl unload ~/Library/LaunchAgents/com.example.PingMenuBar.plist
rm ~/Library/LaunchAgents/com.example.PingMenuBar.plist
```

If you used Login Items:
- Go to **System Settings → General → Login Items**
- Select PingMenuBar and click the **-** button

## Testing

After installation, log out and log back in. The ping menu bar icon should appear automatically!
