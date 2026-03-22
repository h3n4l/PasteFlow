# Auto-Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add check-for-update and update-in-place functionality so users get notified of new versions and can update with one click.

**Architecture:** AppUpdater library (ObservableObject) checks GitHub Releases for newer `.zip` assets. On launch, a silent check sets state. Users trigger install from Settings (About tab) or menu bar. AppUpdater handles download, code signing verification, bundle replacement, and relaunch. All update code is gated behind `ENABLE_AUTO_UPDATE` compile flag.

**Tech Stack:** Swift 5, SwiftUI, s1ntoneli/AppUpdater (0.2.0+), GitHub Releases API

**Spec:** `docs/superpowers/specs/2026-03-22-auto-update-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `PasteFlow.xcodeproj/project.pbxproj` | Modify | Add `ENABLE_AUTO_UPDATE` to `SWIFT_ACTIVE_COMPILATION_CONDITIONS` for Debug and Release |
| Xcode SPM dependencies | Modify | Add AppUpdater package |
| `PasteFlow/Services/UpdateService.swift` | Create | Wraps AppUpdater, exposes update state to AppState |
| `PasteFlow/State/AppState.swift` | Modify | Add optional `UpdateService` reference and convenience properties |
| `PasteFlow/App/AppDelegate.swift` | Modify | Initialize UpdateService, trigger launch check |
| `PasteFlow/Views/SettingsView.swift` | Modify | Add update UI to About tab |
| `PasteFlow/App/PasteFlowApp.swift` | Modify | Add "Update Available" menu item to both MenuBarMenuView variants |
| `.github/workflows/release.yml` | Modify | Add zip asset alongside DMG |

---

### Task 1: Add AppUpdater SPM Dependency

**Files:**
- Modify: `PasteFlow.xcodeproj/project.pbxproj` (via Xcode CLI or manual SPM resolution)

- [ ] **Step 1: Add AppUpdater package via xcodebuild**

Since PasteFlow uses Xcode's built-in SPM (not a standalone Package.swift), add the dependency through the Xcode project. Add to `project.pbxproj` the package reference:

```
Package URL: https://github.com/s1ntoneli/AppUpdater.git
Version: 0.2.0 (up to next major)
```

This must be done by editing `project.pbxproj` to add:
1. An `XCRemoteSwiftPackageReference` entry for AppUpdater
2. An `XCSwiftPackageProductDependency` for the `AppUpdater` product in the PasteFlow target

- [ ] **Step 2: Add ENABLE_AUTO_UPDATE compilation condition**

Edit `PasteFlow.xcodeproj/project.pbxproj` to add `ENABLE_AUTO_UPDATE` to `SWIFT_ACTIVE_COMPILATION_CONDITIONS` in both build configurations:

- Debug config (has existing `"DEBUG $(inherited)"`): change to `"DEBUG ENABLE_AUTO_UPDATE $(inherited)"`
- Release config (no existing value): add `SWIFT_ACTIVE_COMPILATION_CONDITIONS = "ENABLE_AUTO_UPDATE $(inherited)";`

These are in the **project-level** build settings (section IDs `2FEBB3222F6BC9AA00FEA936` for Debug, `2FEBB3232F6BC9AA00FEA936` for Release).

- [ ] **Step 3: Verify the project builds**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project PasteFlow.xcodeproj -scheme PasteFlow -configuration Debug build
```
Expected: BUILD SUCCEEDED with AppUpdater resolved

- [ ] **Step 4: Commit**

```bash
git add PasteFlow.xcodeproj/
git commit -m "build: add AppUpdater dependency and ENABLE_AUTO_UPDATE flag"
```

---

### Task 2: Create UpdateService

**Files:**
- Create: `PasteFlow/Services/UpdateService.swift`

- [ ] **Step 1: Create UpdateService.swift**

```swift
#if ENABLE_AUTO_UPDATE
import AppUpdater
import Combine
import Foundation
import os.log

/// Wraps AppUpdater to expose update state for SwiftUI views.
/// Not annotated @MainActor to match AppState's pattern — all @Published
/// updates happen on main thread via Combine observation of AppUpdater's state.
final class UpdateService: ObservableObject {
    private let updater: AppUpdater
    private let logger = Logger(subsystem: "com.github.h3n4l.PasteFlow", category: "UpdateService")
    private var cancellable: AnyCancellable?

    @Published var updateAvailable = false
    @Published var newVersion: String?
    @Published var isChecking = false
    @Published var isDownloading = false
    @Published var downloadReady = false
    @Published var isInstalling = false
    @Published var isUpToDate = false
    @Published var error: String?

    init() {
        self.updater = AppUpdater(owner: "h3n4l", repo: "PasteFlow")

        // Observe AppUpdater's state transitions via Combine
        cancellable = updater.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .none:
                    self.isDownloading = false
                    self.downloadReady = false
                case .newVersionDetected(let release, _):
                    self.updateAvailable = true
                    self.newVersion = release.tagName.description
                    self.isDownloading = false
                    self.downloadReady = false
                case .downloading(let release, _, _):
                    self.updateAvailable = true
                    self.newVersion = release.tagName.description
                    self.isDownloading = true
                    self.downloadReady = false
                case .downloaded(let release, _, _):
                    self.updateAvailable = true
                    self.newVersion = release.tagName.description
                    self.isDownloading = false
                    self.downloadReady = true
                }
            }
    }

    /// Check for updates. If `silent` is true (launch check), errors are suppressed.
    func checkForUpdates(silent: Bool = false) {
        isChecking = true
        isUpToDate = false
        error = nil

        updater.check(
            success: { [weak self] in
                guard let self else { return }
                self.isChecking = false
                if !self.updateAvailable && !silent {
                    self.isUpToDate = true
                }
                if self.updateAvailable {
                    self.logger.info("Update available: \(self.newVersion ?? "unknown")")
                } else {
                    self.logger.info("Already up to date")
                }
            },
            fail: { [weak self] err in
                guard let self else { return }
                self.isChecking = false
                if !silent {
                    self.error = "Couldn't check for updates. Please check your connection."
                }
                self.logger.error("Update check failed: \(err.localizedDescription)")
            }
        )
    }

    /// Install the downloaded update. Only callable when downloadReady is true.
    /// Replaces the app bundle and relaunches.
    func installUpdate() {
        guard case .downloaded(_, _, let bundle) = updater.state else {
            error = "Update not ready for installation."
            return
        }

        isInstalling = true
        error = nil

        do {
            try updater.installThrowing(bundle)
            // App will terminate and relaunch — we won't reach here
        } catch {
            self.isInstalling = false
            self.error = "Update failed: \(error.localizedDescription)"
            logger.error("Install failed: \(error.localizedDescription)")
        }
    }
}
#endif
```

- [ ] **Step 2: Verify the project builds**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project PasteFlow.xcodeproj -scheme PasteFlow -configuration Debug build
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add PasteFlow/Services/UpdateService.swift
git commit -m "feat: add UpdateService wrapping AppUpdater"
```

---

### Task 3: Wire UpdateService into AppState and AppDelegate

**Files:**
- Modify: `PasteFlow/State/AppState.swift`
- Modify: `PasteFlow/App/AppDelegate.swift`

- [ ] **Step 1: Add UpdateService to AppState**

In `PasteFlow/State/AppState.swift`, add an optional published property for the update service. Add inside the `AppState` class, after the existing `@Published` properties:

```swift
#if ENABLE_AUTO_UPDATE
@Published var updateService: UpdateService?
#endif
```

- [ ] **Step 2: Initialize UpdateService in AppDelegate and trigger launch check**

In `PasteFlow/App/AppDelegate.swift`, inside `applicationDidFinishLaunching`, at the end of the `do` block (before the `} catch {` on line 62), add:

```swift
#if ENABLE_AUTO_UPDATE
let updateService = UpdateService()
state.updateService = updateService
updateService.checkForUpdates(silent: true)
#endif
```

- [ ] **Step 3: Verify the project builds**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project PasteFlow.xcodeproj -scheme PasteFlow -configuration Debug build
```
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add PasteFlow/State/AppState.swift PasteFlow/App/AppDelegate.swift
git commit -m "feat: wire UpdateService into AppState and trigger launch check"
```

---

### Task 4: Add Update UI to Settings About Tab

**Files:**
- Modify: `PasteFlow/Views/SettingsView.swift`

- [ ] **Step 1: Add update UI to the aboutTab**

Replace the `aboutTab` computed property in `SettingsView.swift` (lines 130-139) with a version that includes update controls:

```swift
private var aboutTab: some View {
    VStack(spacing: 12) {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable().frame(width: 64, height: 64)
        Text("PasteFlow").font(.headline)
        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
            .foregroundColor(.secondary)
        Link("GitHub", destination: URL(string: "https://github.com/h3n4l/PasteFlow")!)

        #if ENABLE_AUTO_UPDATE
        Divider().padding(.horizontal, 40)
        updateSection
        #endif
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
}
```

Then add a new computed property for the update section. Note: this needs a `@State private var showUpdateConfirmation = false` added to `SettingsView` (gated behind `#if ENABLE_AUTO_UPDATE`):

```swift
#if ENABLE_AUTO_UPDATE
@State private var showUpdateConfirmation = false
#endif
```

```swift
#if ENABLE_AUTO_UPDATE
@ViewBuilder
private var updateSection: some View {
    if let updateService = appState.updateService {
        if updateService.isInstalling {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Installing update...")
            }
        } else if updateService.isDownloading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Downloading update...")
            }
        } else if updateService.isChecking {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking for updates...")
            }
        } else if updateService.downloadReady, let version = updateService.newVersion {
            VStack(spacing: 6) {
                Text("PasteFlow \(version) is available")
                    .foregroundColor(.secondary)
                    .font(.callout)
                Button("Update Now") {
                    showUpdateConfirmation = true
                }
                .alert("Update Available", isPresented: $showUpdateConfirmation) {
                    Button("Update Now") {
                        updateService.installUpdate()
                    }
                    Button("Later", role: .cancel) {}
                } message: {
                    let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
                    Text("PasteFlow \(version) is available. You're running v\(current). The app will restart after updating.")
                }
            }
        } else if updateService.updateAvailable, let version = updateService.newVersion {
            VStack(spacing: 6) {
                Text("PasteFlow \(version) is available, preparing download...")
                    .foregroundColor(.secondary)
                    .font(.callout)
            }
        } else if updateService.isUpToDate {
            Text("You're running the latest version")
                .foregroundColor(.secondary)
                .font(.callout)
        } else if let error = updateService.error {
            VStack(spacing: 6) {
                Text(error)
                    .foregroundColor(.red)
                    .font(.callout)
                Button("Retry") {
                    updateService.checkForUpdates()
                }
            }
        } else {
            Button("Check for Updates") {
                updateService.checkForUpdates()
            }
        }
    }
}
#endif
```

- [ ] **Step 2: Increase frame height to accommodate update section**

In the `body` property, change the frame height from 280 to 340:

```swift
}.frame(width: 480, height: 340)
```

- [ ] **Step 3: Verify the project builds**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project PasteFlow.xcodeproj -scheme PasteFlow -configuration Debug build
```
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add PasteFlow/Views/SettingsView.swift
git commit -m "feat: add update controls to Settings About tab"
```

---

### Task 5: Add "Update Available" Menu Item

**Files:**
- Modify: `PasteFlow/App/PasteFlowApp.swift`

- [ ] **Step 1: Add update menu item to MenuBarMenuView14**

In `MenuBarMenuView14`, add the "Update Available" item between the Divider and "Settings..." button. The view needs to observe `appState` from `appDelegate`:

```swift
@available(macOS 14.0, *)
struct MenuBarMenuView14: View {
    let appDelegate: AppDelegate
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Open PasteFlow") { appDelegate.togglePanel() }
            .keyboardShortcut("v", modifiers: [.command, .shift])
        Divider()
        #if ENABLE_AUTO_UPDATE
        if appDelegate.appState.updateService?.updateAvailable == true,
           let version = appDelegate.appState.updateService?.newVersion {
            Button("Update Available (\(version))") {
                appDelegate.showSettings()
                DispatchQueue.main.async {
                    openSettings()
                }
            }
        }
        #endif
        Button("Settings...") {
                appDelegate.showSettings()
                DispatchQueue.main.async {
                    openSettings()
                }
            }
            .keyboardShortcut(",", modifiers: .command)
        Button("Quit PasteFlow") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
```

- [ ] **Step 2: Add update menu item to MenuBarMenuView13**

Same pattern for `MenuBarMenuView13`:

```swift
struct MenuBarMenuView13: View {
    let appDelegate: AppDelegate

    var body: some View {
        Button("Open PasteFlow") { appDelegate.togglePanel() }
            .keyboardShortcut("v", modifiers: [.command, .shift])
        Divider()
        #if ENABLE_AUTO_UPDATE
        if appDelegate.appState.updateService?.updateAvailable == true,
           let version = appDelegate.appState.updateService?.newVersion {
            Button("Update Available (\(version))") {
                appDelegate.showSettings()
                DispatchQueue.main.async {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            }
        }
        #endif
        Button("Settings...") {
            appDelegate.showSettings()
            DispatchQueue.main.async {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
        .keyboardShortcut(",", modifiers: .command)
        Button("Quit PasteFlow") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
```

- [ ] **Step 3: Verify the project builds**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project PasteFlow.xcodeproj -scheme PasteFlow -configuration Debug build
```
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add PasteFlow/App/PasteFlowApp.swift
git commit -m "feat: add 'Update Available' menu item to menu bar"
```

---

### Task 6: Update Release Workflow to Produce Zip Asset

**Files:**
- Modify: `.github/workflows/release.yml`

- [ ] **Step 1: Add zip creation step to release workflow**

In `.github/workflows/release.yml`, after the "Create DMG" step (after line 89), add a new step to create a zip of the `.app` bundle:

```yaml
      - name: Create ZIP for auto-update
        run: |
          APP_PATH="build/DerivedData/Build/Products/Release/PasteFlow.app"
          VERSION="${{ steps.version.outputs.version }}"
          ZIP_PATH="build/PasteFlow-${VERSION}.zip"
          cd "$(dirname "$APP_PATH")"
          zip -r -y "${GITHUB_WORKSPACE}/${ZIP_PATH}" "PasteFlow.app"
          echo "ZIP_PATH=${ZIP_PATH}" >> "$GITHUB_ENV"
          echo "ZIP created: $(du -h "${GITHUB_WORKSPACE}/${ZIP_PATH}" | cut -f1)"
```

Note: `-y` preserves symlinks in the app bundle (important for frameworks).

- [ ] **Step 2: Add zip to the release upload**

In the `gh release create` command (line 106), add the zip path:

Change:
```yaml
            "$DMG_PATH"
```
To:
```yaml
            "$DMG_PATH" \
            "$ZIP_PATH"
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add zip asset to releases for auto-update"
```

---

### Task 7: Update Spec and Final Verification

**Files:**
- Modify: `docs/superpowers/specs/2026-03-22-auto-update-design.md`

- [ ] **Step 1: Run full build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project PasteFlow.xcodeproj -scheme PasteFlow -configuration Debug build
```
Expected: BUILD SUCCEEDED

- [ ] **Step 2: Run tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project PasteFlow.xcodeproj -scheme PasteFlow \
  build-for-testing -destination 'platform=macOS'
```
Expected: BUILD SUCCEEDED (tests compile and existing tests still pass)

- [ ] **Step 3: Commit spec updates**

```bash
git add docs/superpowers/specs/2026-03-22-auto-update-design.md
git commit -m "docs: update spec with zip asset requirement and AppUpdater API findings"
```
