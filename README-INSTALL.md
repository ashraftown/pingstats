# Install notes

Prefer the main [README](README.md).

## DMG (unsigned release)

1. Drag **PingMenuBar** to Applications  
2. Open Terminal and run:

```bash
xattr -cr /Applications/PingMenuBar.app && open /Applications/PingMenuBar.app
```

Or, with the DMG still mounted:

```bash
bash "/Volumes/PingMenuBar/install.sh"
```

Do **not** double-click the app or `install.sh` for the first open — Gatekeeper blocks both the same way.

## Build from source

Build **Release** in Xcode and copy `PingMenuBar.app` to `/Applications`.

## Open at Login

Use the in-app **Open at Login** checkbox (recommended).

## Optional LaunchAgent script

```bash
./install-launch-agent.sh
```

This copies a DerivedData build into `/Applications` and registers a LaunchAgent.  
Do **not** enable both the LaunchAgent and the in-app **Open at Login** checkbox.
