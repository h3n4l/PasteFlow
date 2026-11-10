<p align="center">
  <img src="assets/screenshots/app-icon.png" width="128" height="128" alt="PasteFlow icon">
</p>

<h1 align="center">PasteFlow</h1>

<p align="center">Smooth, flowing clipboard history on macOS — free and open source.</p>

![PasteFlow](assets/screenshots/hero.png)

## Install

### Download

Download the latest `.dmg` from [Releases](https://github.com/h3n4l/PasteFlow/releases), open it, and drag PasteFlow to Applications.

![Install](assets/screenshots/dmg.png)

### Bypass Gatekeeper

> [!IMPORTANT]
> Since PasteFlow is not notarized with Apple, macOS will block it on first launch. You only need to allow it once.

![Allow PasteFlow in System Settings](assets/screenshots/open-anyway.png)

1. Open PasteFlow from Applications. macOS warns that it could not verify the app — click **Done** (**Cancel** or **OK** on older macOS), not **Move to Trash**.
2. Open **System Settings → Privacy & Security**, scroll down to **Security**, and click **Open Anyway** next to "PasteFlow was blocked". The button is only there for about an hour after step 1.
3. In the dialog that follows, click **Open Anyway** again, then confirm with your Mac password or Touch ID.

Comfortable with the Terminal? This one command does the same thing:

```bash
sudo xattr -rd com.apple.quarantine /Applications/PasteFlow.app
```

### First Launch

1. Open PasteFlow from Applications
2. Grant **Accessibility** permission when prompted (required for auto-paste)
3. PasteFlow appears in your menu bar — press `Cmd+Shift+V` to get started

## Features

- **Instant access** — press `Cmd+Shift+V` to open your clipboard history from anywhere
- **Smart categorization** — text, code, links, and images are auto-detected and tagged
- **Search & filter** — find any copied item instantly with search or filter by type
- **Quick paste** — select an item and press Enter to paste directly into your app
- **Keyboard-first** — arrow keys to navigate, `Cmd+1`–`9` to quick-paste, Tab to cycle filters, Esc to dismiss
- **Image support** — screenshots and copied images stored in original format (PNG, TIFF, JPEG, etc.)
- **Lightweight** — lives in your menu bar, no Dock icon, stays out of your way
- **Privacy-first** — all data stored locally, nothing leaves your Mac
- **Configurable retention** — keep history for 7 to 90 days

## Usage

| Shortcut | Action |
|---|---|
| `Cmd+Shift+V` | Open / close PasteFlow |
| `↑` / `↓` | Navigate items |
| `Enter` | Paste selected item |
| `Cmd+1` – `Cmd+9` | Quick paste Nth item |
| `Tab` | Cycle filter (All → Text → Link → Code → Image) |
| `Esc` | Dismiss |
| Type anything | Search your clipboard history |

## Requirements

- macOS 13.0 (Ventura) or later
- Accessibility permission (for paste simulation)

## Build from Source

```bash
# Clone
git clone https://github.com/h3n4l/PasteFlow.git
cd PasteFlow

# Build
xcodebuild -project PasteFlow.xcodeproj -scheme PasteFlow -configuration Release build

# Or open in Xcode
open PasteFlow.xcodeproj
```

### Create DMG

```bash
brew install create-dmg
./scripts/create-dmg.sh
```

## Tech Stack

- **Swift 5** + **SwiftUI** — all UI
- **AppKit** — NSPanel for floating window, Carbon API for global hotkey
- **GRDB** (SQLite) — clipboard history persistence
- **CGEvent** — paste simulation

## License

[GPL-3.0](LICENSE)

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.
