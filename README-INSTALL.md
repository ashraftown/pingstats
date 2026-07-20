# Install notes

Prefer the main [README](README.md):

- **DMG** from GitHub Releases (drag to Applications)
- **First open:** double-click **Open PingMenuBar** on the DMG (unsigned builds)
- Fallback: `xattr -cr /Applications/PingMenuBar.app && open /Applications/PingMenuBar.app`
- Or build **Release** in Xcode and copy `PingMenuBar.app` to `/Applications`
- **Open at Login** from the app popup (recommended)

## Optional LaunchAgent script

```bash
./install-launch-agent.sh
```

This copies a DerivedData build into `/Applications` and registers a LaunchAgent.  
Do **not** enable both the LaunchAgent and the in-app **Open at Login** checkbox.
