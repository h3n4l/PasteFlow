# Auto-Update Design Spec

**Date:** 2026-03-22
**Status:** Approved

## Overview

Add check-for-update and update-in-place functionality to PasteFlow so users don't need to manually download and install new versions. Updates are delivered through GitHub Releases using the s1ntoneli/AppUpdater library.

## Goals

- Users are notified when a new version is available
- One-click update: download, replace, relaunch — no manual steps
- Zero changes to the existing release workflow
- Designed to be excluded from a future App Store build

## Non-Goals

- Delta updates (patch-only downloads)
- Built-in release notes viewer
- Periodic background checking while the app is running
- App Store distribution (future project)

## Approach: s1ntoneli/AppUpdater

A pure Swift library that checks GitHub Releases for newer versions, downloads the asset, verifies code signing identity, replaces the `.app` bundle, and relaunches.

**Why AppUpdater over Sparkle:**
- Works directly with GitHub Releases — no appcast XML or EdDSA key management
- Pure Swift with async/await and ObservableObject — fits PasteFlow's architecture
- Minimal dependency (~single file)
- No extra infrastructure needed; existing release workflow already produces correctly named assets

**Why AppUpdater over rolling our own:**
- Handles the hard parts: DMG extraction, code signing verification, atomic bundle replacement, relaunch
- Avoids re-inventing solved edge cases (permissions, partial downloads, file locks)

## Asset Naming Requirement

AppUpdater requires GitHub Release assets to follow the pattern:

```
\(name)-\(semanticVersion).ext
```

The existing release workflow already produces `PasteFlow-x.y.z.dmg`, which satisfies this requirement. No CI changes needed.

## Dependencies & Build Configuration

- Add **s1ntoneli/AppUpdater** via Swift Package Manager
- Add a compile flag `ENABLE_AUTO_UPDATE` to the build settings
  - Set to `true` for the direct-download build (current)
  - Can be set to `false` for a future App Store target
- All update-related code is gated behind `#if ENABLE_AUTO_UPDATE`

## UpdateService

A new service at `PasteFlow/Services/UpdateService.swift`:

- Conforms to `ObservableObject` (consistent with existing services)
- Wraps AppUpdater's API

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `updateAvailable` | `Bool` | Whether a newer version was found |
| `newVersion` | `String?` | The version string of the available update |
| `isDownloading` | `Bool` | Whether an update is being downloaded/installed |
| `error` | `String?` | Error message to display to user |

### Methods

| Method | Trigger | Description |
|--------|---------|-------------|
| `checkForUpdates()` | On launch, manual button | Checks GitHub Releases API for a newer version |
| `installUpdate()` | User clicks "Update Now" | Downloads, verifies, replaces, relaunches |

### Integration with AppState

`AppState` gets an optional `UpdateService` reference and exposes its state to views. This follows the existing pattern where `AppState` is the single source of truth.

## Update Check Triggers

1. **On app launch** — automatic, silent check. If no update is found or network is unavailable, no UI is shown.
2. **Manual** — "Check for Updates" button in Settings. Always shows a result (up-to-date, update available, or error).

No periodic background checks while the app is running.

## UI Changes

### Settings View

Add an "Updates" section to the existing Settings view:

- Display current version (from `Bundle.main`)
- "Check for Updates" button
- States:
  - **Idle:** Button reads "Check for Updates"
  - **Checking:** Button disabled, shows spinner
  - **Update available:** Shows "PasteFlow vX.Y.Z is available" with "Update Now" button
  - **Downloading:** Shows progress indicator
  - **Up to date:** Shows "You're running the latest version"
  - **Error:** Shows error message with retry option

### Menu Bar Indicator

When an update is available:
- Add an "Update Available" menu item to the menu bar menu
- Clicking it opens the update prompt

### Update Prompt

Simple alert dialog shown when an update is found (on launch or manual check):

- Title: "Update Available"
- Message: "PasteFlow vX.Y.Z is available. You're running vX.Y.Z."
- Buttons: "Update Now" / "Later"
- "Update Now" triggers download, replace, and relaunch

## Update Flow

### Happy Path

1. App launches → `UpdateService.checkForUpdates()` queries GitHub Releases API
2. Compares latest release semantic version against `Bundle.main` version
3. If newer version found → sets `updateAvailable = true`
4. User sees indicator (menu item or Settings) and clicks "Update Now"
5. AppUpdater downloads `PasteFlow-x.y.z.dmg`
6. Extracts `.app` from DMG, verifies code signing identity matches running app
7. Moves old `.app` to trash, moves new `.app` into place
8. Relaunches the new version

### Error Cases

| Scenario | Behavior |
|----------|----------|
| No network (launch check) | Silent failure, no UI shown |
| No network (manual check) | Show: "Couldn't reach GitHub. Check your connection." |
| Download fails | Show error with retry option |
| Signature mismatch | Abort update, show: "Update verification failed" |
| Permission denied | Show error explaining user needs to move app or update manually |
| Already up to date (manual) | Show: "You're running the latest version" |

## Release Workflow

No changes needed. The existing workflow:

1. Validates version from `release/x.y.z` branch against `VERSION` file
2. Builds Release configuration
3. Creates `PasteFlow-x.y.z.dmg`
4. Creates draft GitHub Release with DMG attached

Draft releases are not visible to AppUpdater. The release becomes discoverable once manually published — this is intentional, giving the maintainer a chance to review before users see it.

## Future App Store Compatibility

When a Mac App Store build is eventually created:

- The App Store handles updates — no custom updater needed
- The `ENABLE_AUTO_UPDATE` flag is set to `false` for the App Store target
- All update-related code compiles out via `#if ENABLE_AUTO_UPDATE`
- No update UI is shown to App Store users
- The rest of the codebase is unaffected

## Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `Package.swift` / Xcode SPM | Modify | Add AppUpdater dependency |
| `PasteFlow/Services/UpdateService.swift` | Create | New update service |
| `PasteFlow/State/AppState.swift` | Modify | Add UpdateService reference |
| `PasteFlow/Views/SettingsView.swift` | Modify | Add Updates section |
| `PasteFlow/App/PasteFlowApp.swift` or `AppDelegate.swift` | Modify | Trigger launch check |
| Build settings | Modify | Add `ENABLE_AUTO_UPDATE` flag |
