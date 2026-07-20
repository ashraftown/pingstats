<div align="center">

# PingMenuBar

**A tiny macOS menu bar app for live network latency.**

Glanceable RTT in your menu bar · rolling min/avg/max · pinable popup · open at login

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?style=flat-square&logo=apple)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-5-F05138?style=flat-square&logo=swift&logoColor=white)](#build-from-source)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)
[![Release](https://img.shields.io/badge/release-DMG-blue?style=flat-square)](#install)

<br />

<img src="Screenshot.png" alt="PingMenuBar screenshot" width="420" />

<br />

**Drag · Drop · Terminal once** — release DMGs use the classic Applications layout; first open needs a one-line Terminal command (unsigned builds).

</div>

---

## Features

| | |
|---|---|
| **Menu bar** | Latest ping (ms) with color: green &lt;50 · yellow &lt;100 · orange &lt;200 · red ≥200 |
| **Popup** | Latest, min/avg/max, resolved IP, live bar graph |
| **Host** | Any IP or hostname (default `8.8.8.8`) |
| **Interval** | 1s / 2s / 5s / 10s / 30s (persisted) |
| **Pin** | Keep the popup open while you work elsewhere |
| **Open at Login** | System Login Items via `SMAppService` |
| **Quiet** | `LSUIElement` — no Dock icon |

---

## Install

### DMG (recommended)

1. Download **`PingMenuBar-*.dmg`** from the repo **Releases** page
2. Open the DMG and open **START HERE.txt**
3. Drag **PingMenuBar** onto **Applications**
4. **First open** — paste this into **Terminal** and press Return:

```bash
xattr -cr /Applications/PingMenuBar.app && open /Applications/PingMenuBar.app
```

5. Later opens: Applications or Spotlight as usual  
6. Optional: enable **Open at Login** in the app popup

> **Why Terminal?** Releases are **not** Apple-notarized. On modern macOS, double-clicking an  
> unsigned download (the **app or a `.command` helper**) hits the same Gatekeeper block:  
> *“Apple could not verify…”* with **Done** / **Move to Bin**. That dialog cannot be customized.  
> Running `xattr` in Terminal clears quarantine once; after that, normal double-click works.
>
> **Alternatives on the DMG:** run `bash /Volumes/PingMenuBar/install.sh`, or open  
> **Privacy & Security** → **Open Anyway** after trying the app once.

### Build from source

```bash
git clone <your-fork-or-repo-url>.git
cd pingmenubar
open PingMenuBar.xcodeproj
```

In Xcode: scheme **PingMenuBar**, configuration **Release**, then **Product → Build** (⌘B).

Copy:

```text
~/Library/Developer/Xcode/DerivedData/PingMenuBar-*/Build/Products/Release/PingMenuBar.app
```

into `/Applications`.

---

## Usage

1. **Menu bar** — latest RTT + status color  
2. **Click icon** — popup with stats, graph, host & interval  
3. **Click outside** — dismiss (or use **pin** to keep open)  
4. **Stop → edit host → Start** — change target  
5. **Every** — change ping interval  
6. **Open at Login** — bottom-left checkbox  
7. **Quit PingMenuBar** — bottom-right  

---

## How it works

- Shells out to `/sbin/ping -c 1` and parses `time=… ms` (same numbers as Terminal)
- Menu bar shows the **latest** sample; popup keeps **min/avg/max** over the last 30 successes
- Sandbox is **off** so `ping` can run
- Requires **macOS 13+**

---

## Releases (DMG via GitHub Actions)

Pushing a version tag builds a **drag-to-Applications** DMG on `macos-14` and attaches it to a GitHub Release:

```bash
git tag v1.0.0
git push origin v1.0.0
```

Workflow: [`.github/workflows/release.yml`](.github/workflows/release.yml)

What you get in the DMG:

- `PingMenuBar.app` (left) + shortcut to **Applications** (right)
- **START HERE.txt** — first-open instructions (Terminal one-liner)
- **install.sh** — optional installer; run via Terminal (`bash …`), not double-click
- **Privacy & Security.webloc** — jumps to System Settings for **Open Anyway**
- Custom Finder background (`assets/dmg-background.png`) via [`create-dmg`](https://github.com/create-dmg/create-dmg)

You can also run the workflow manually (**Actions → Release → Run workflow**) to produce an artifact without a tag.

Local DMG (on a Mac, after a Release build):

```bash
brew install create-dmg   # optional but prettier layout
./scripts/create-dmg.sh /path/to/PingMenuBar.app dist/PingMenuBar.dmg
```

---

## Project layout

```text
pingmenubar/
├── PingMenuBar/                 # App sources
│   ├── PingMenuBarApp.swift     # App, menu bar, popup UI, login item
│   ├── PingManager.swift        # Ping + stats
│   ├── Assets.xcassets/
│   ├── Info.plist
│   └── PingMenuBar.entitlements
├── PingMenuBar.xcodeproj/
├── assets/
│   ├── dmg-background.png       # Finder window background (1x)
│   └── dmg-background@2x.png    # Retina source
├── scripts/
│   ├── create-dmg.sh                # DMG packager
│   ├── START HERE.txt               # First-open instructions (staged into DMG)
│   ├── install.sh                   # Terminal installer (staged into DMG)
│   └── Privacy & Security.webloc    # Opens Privacy & Security settings
├── .github/workflows/release.yml
├── Screenshot.png
├── LICENSE
└── README.md
```

---

## Credits

This project started from **[MenuPIng](https://github.com/NimbleAINinja/MenuPIng)** by **[NimbleAINinja](https://github.com/NimbleAINinja)** — thank you for the original menu bar ping app and structure.

PingMenuBar continues that idea with UX and packaging changes (latest-in-menu-bar, interval control, pin, open-at-login, DMG releases, and related fixes).

---

## Requirements

- macOS **13.0** or later  
- Xcode **15+** to build from source  

---

## License

[MIT](LICENSE) — see the license file for full terms. Original MenuPIng work is credited above; this repository is also under MIT.
