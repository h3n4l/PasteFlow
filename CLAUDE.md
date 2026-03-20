# PasteFlow

Smooth, flowing clipboard history on macOS — free and open source.

## Tech Stack

- **Language:** Swift 5
- **UI Framework:** SwiftUI
- **Platform:** macOS 15.2+ (native app)
- **IDE:** Xcode (project: `PasteFlow.xcodeproj`)
- **Bundle ID:** `com.github.h3n4l.PasteFlow`

## Project Structure

```
PasteFlow/               # Main app source
  PasteFlowApp.swift     # App entry point (@main)
  ContentView.swift      # Root view
  Assets.xcassets/       # App icon, menu bar icon, accent color
PasteFlowTests/          # Unit tests
PasteFlowUITests/        # UI tests
```

## Build & Run

```bash
# Build
xcodebuild -project PasteFlow.xcodeproj -scheme PasteFlow -configuration Debug build

# Run tests
xcodebuild -project PasteFlow.xcodeproj -scheme PasteFlow test

# Clean
xcodebuild -project PasteFlow.xcodeproj -scheme PasteFlow clean
```

## Conventions

- Use SwiftUI for all UI — no AppKit unless absolutely necessary
- Follow Swift naming conventions (camelCase for properties/methods, PascalCase for types)
- Each view gets its own file
- Use `#Preview` macros for SwiftUI previews
- Keep views small and composable; extract subviews when a view body exceeds ~50 lines
