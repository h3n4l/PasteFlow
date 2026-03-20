# PasteFlow

Smooth, flowing clipboard history on macOS — free and open source.

## Tech Stack

- **Language:** Swift 5
- **UI Framework:** SwiftUI + AppKit (NSPanel for floating window)
- **Persistence:** GRDB (SQLite) via Swift Package Manager
- **Platform:** macOS 13.0+ (Ventura)
- **IDE:** Xcode (project: `PasteFlow.xcodeproj`)
- **Bundle ID:** `com.github.h3n4l.PasteFlow`
- **Distribution:** Direct download (not Mac App Store — sandbox is disabled)

## Architecture

Menu bar app (LSUIElement) with a global hotkey (`Cmd+Shift+V`) that shows a centered floating panel. No Dock icon.

- **AppState** (ObservableObject) is the single source of truth for all UI state
- **StorageService** handles SQLite persistence via GRDB, images stored as files on disk
- **ClipboardMonitor** polls NSPasteboard every 0.5s for new content
- **HotkeyService** registers global hotkey via Carbon API
- **PasteSimulator** copies to pasteboard and simulates Cmd+V via CGEvent
- **FloatingPanel** (NSPanel subclass) hosts all SwiftUI views via NSHostingView

## Project Structure

```
PasteFlow/
  App/                    — PasteFlowApp.swift (@main, MenuBarExtra), AppDelegate.swift
  Models/                 — ClipboardItem, ClipboardItemRecord (GRDB), ContentType, ImageFormat
  State/                  — AppState.swift (central ObservableObject)
  Services/               — ClipboardMonitor, StorageService, HotkeyService, PasteSimulator
  Views/                  — PopoverView, SearchBarView, FilterRowView, ClipListView,
                            ClipRowView, DetailPanelView, FooterView, SettingsView,
                            FloatingPanel (NSPanel)
  Utilities/              — ContentClassifier, Extensions (Date, Color helpers)
  Assets.xcassets/        — App icon, menu bar icon, accent color
PasteFlowTests/           — Unit tests (Models/, Services/, Utilities/)
PasteFlowUITests/         — UI tests
docs/superpowers/
  specs/                  — Design spec
  plans/                  — Implementation plan
```

## Build & Run

```bash
# Build (requires Xcode — set DEVELOPER_DIR if xcode-select points to CommandLineTools)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project PasteFlow.xcodeproj -scheme PasteFlow -configuration Debug build

# Run tests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project PasteFlow.xcodeproj -scheme PasteFlow test -destination 'platform=macOS'

# Clean
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project PasteFlow.xcodeproj -scheme PasteFlow clean
```

## Key Dependencies

- **GRDB.swift** (7.0+) — SQLite database via SPM

## Conventions

- SwiftUI for all UI; AppKit only for FloatingPanel (NSPanel) and system integrations
- Follow Swift naming conventions (camelCase for properties/methods, PascalCase for types)
- Each view gets its own file
- State flows through AppState — views observe it via @ObservedObject
- Images stored on disk at `~/Library/Application Support/PasteFlow/images/`
- Database at `~/Library/Application Support/PasteFlow/clipboard.db`
- Content types auto-detected by ContentClassifier (URL → link, code heuristics → code, else → text)
- Xcode project uses PBXFileSystemSynchronizedRootGroup — new files are auto-discovered, no pbxproj edits needed
