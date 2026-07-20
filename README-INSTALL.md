# Install notes

Prefer the main [README](README.md).

## DMG (unsigned release)

1. Drag **PingMenuBar** to Applications  
2. Open the app once (warning → **Done**)  
3. Open **How to Open** on the DMG and use **Open Privacy & Security**,  
   or go to **System Settings → Privacy & Security**  
4. Click **Open Anyway** for PingMenuBar  

No install scripts — double-clicked helpers are blocked the same way as the app.

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
