# PasteFlow MVP Design Spec

## Overview

PasteFlow is a free, open-source clipboard history manager for macOS. It monitors the system clipboard, stores copied items, and lets users quickly search and re-paste from their history via a global hotkey.

**Target audience:** General Mac users — designers, writers, developers, students.
**Minimum macOS version:** 13.0 (Ventura)
**Tech stack:** Swift, SwiftUI, GRDB (SQLite), AppKit (NSPanel only)
**Distribution:** Direct download / Homebrew cask (not Mac App Store — sandbox restrictions prevent core functionality).

## Sandbox & Entitlements

App Sandbox must be **disabled**. The following core features are incompatible with sandboxing:

- `CGEvent` posting for paste simulation (requires Accessibility)
- `RegisterEventHotKey` for global hotkey registration
- Unrestricted `NSPasteboard` access for clipboard monitoring

The app is distributed outside the Mac App Store. Code signing with Developer ID is recommended for Gatekeeper compatibility.

## Activation Model

**Hybrid: Menu bar icon + centered floating panel.**

- A menu bar icon (`MenuBarExtra`) provides access to Settings and Quit.
- `Cmd+Shift+V` toggles a centered floating panel (the main UI).
- Clicking the menu bar icon also opens the floating panel.
- The panel dismisses on Esc, clicking outside, or after pasting.
- The app does not appear in the Dock (`LSUIElement = true`).

**Note on hotkey choice:** `Cmd+Shift+V` conflicts with "Paste and Match Style" in some apps (Safari, Notes, Mail). This is the same hotkey used by popular clipboard managers (Maccy, Clipy). Customizable hotkey is planned for post-MVP to give users an escape hatch.

## Content Types

MVP supports two clipboard content categories:

- **Text** — plain text content, auto-classified into subtypes:
  - **Text** — general plain text
  - **Code** — detected via heuristics (brackets, semicolons, indentation, language keywords)
  - **Link** — detected via URL regex
- **Image** — screenshots, copied images. Stored in original format (PNG, TIFF, JPEG, GIF, BMP, PDF) with no conversion or size limit.

**Not in MVP:** File references. The filter pill for "Files" is hidden.

## Data Model

Two layers: a Swift-side domain model and a flat GRDB database record.

### Domain Model (used by views and services)

```swift
struct ClipboardItem: Identifiable {
    let id: UUID
    let content: ClipboardContent
    let sourceApp: String?
    let createdAt: Date
    var contentType: ContentType
    var characterCount: Int?
    var imageSize: Int?
}

enum ContentType: String, Codable, CaseIterable {
    case text, code, link, image
}

enum ClipboardContent {
    case text(String)
    case image(Data, ImageFormat)
}

enum ImageFormat: String, Codable {
    case png, tiff, jpeg, gif, bmp, pdf
}
```

### Database Record (flat struct for GRDB)

```swift
struct ClipboardItemRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "clipboard_items"

    let id: String              // UUID string
    let contentType: String     // text, code, link, image
    let textContent: String?    // for text types
    let imagePath: String?      // relative path to image file on disk
    let imageFormat: String?    // png, tiff, jpeg, etc.
    let sourceApp: String?
    let createdAt: Double       // Unix timestamp
    let characterCount: Int?
    let imageSize: Int?
    let contentHash: String      // SHA-256 hash for deduplication
}
```

`StorageService` converts between `ClipboardItem` and `ClipboardItemRecord`.

## Storage Layer

**SQLite via GRDB** for metadata. **Filesystem** for image data.

### Database Schema

| Column | Type | Description |
|---|---|---|
| id | TEXT (UUID) | Primary key |
| content_type | TEXT | text, code, link, image |
| text_content | TEXT | Text content (nullable, for text types) |
| image_path | TEXT | Relative path to image file (nullable) |
| image_format | TEXT | png, tiff, jpeg, etc. (nullable) |
| source_app | TEXT | Frontmost app at copy time (nullable) |
| created_at | REAL | Unix timestamp |
| character_count | INTEGER | Character count for text types (nullable) |
| image_size | INTEGER | Byte size for images (nullable) |
| content_hash | TEXT | SHA-256 hash of content (for deduplication) |

### Image Storage

Images are stored as files on disk at `~/Library/Application Support/PasteFlow/images/<uuid>.<format>`. The database stores only the relative path. This avoids SQLite BLOB bloat and keeps the database fast.

When deleting a clipboard item, the corresponding image file is also deleted.

### Key Behaviors

- Search uses SQLite `LIKE` for substring matching on `text_content`.
- Database location: `~/Library/Application Support/PasteFlow/clipboard.db`
- Retention cleanup runs on app launch and every 24 hours — deletes items (and their image files) older than the configured limit.
- `fetchItems` uses `LIMIT`/`OFFSET` pagination to avoid loading all items into memory at once.

### Deduplication

When a new clipboard item matches an existing item (same text content, or same image data hash), the old entry is deleted and a new one is inserted with the current timestamp. This gives "move-to-top" semantics — the most recent copy is always at the top of the list.

### StorageService API

```swift
class StorageService {
    private let dbQueue: DatabaseQueue
    private let imagesDirectory: URL

    func save(_ item: ClipboardItem) throws
    func fetchItems(filter: ContentType?, search: String?,
                    limit: Int, offset: Int) throws -> [ClipboardItem]
    func delete(_ id: UUID) throws
    func deleteExpired(olderThan days: Int) throws
    func itemCount(filter: ContentType?) throws -> Int
}
```

## App State & Services

### AppState (central ObservableObject)

```swift
class AppState: ObservableObject {
    @Published var clipboardItems: [ClipboardItem] = []
    @Published var selectedItem: ClipboardItem?
    @Published var searchText: String = ""
    @Published var activeFilter: ContentType?   // nil = "All"

    let storage: StorageService
    let clipboardMonitor: ClipboardMonitor
    let hotkeyService: HotkeyService

    // Computed property — derives from clipboardItems + searchText + activeFilter.
    // Does not need @Published; SwiftUI re-evaluates it when any
    // @Published dependency changes.
    var filteredItems: [ClipboardItem] { ... }
}
```

### ClipboardMonitor

- Polls `NSPasteboard.general` every ~0.5s using a `Timer`.
- Detects new content by comparing `changeCount`.
- Reads the best available representation (text or image).
- Classifies text content via `ContentClassifier`.
- Captures source app from `NSWorkspace.shared.frontmostApplication`.
- Deduplicates against existing items before saving.
- Notifies `AppState` when a new item is detected.

### HotkeyService

- Registers global `Cmd+Shift+V` hotkey using Carbon `RegisterEventHotKey` API (required because `NSEvent.addGlobalMonitorForEvents` cannot intercept/consume key events).
- Toggles the floating panel visibility.

### PasteSimulator

- Copies the selected item's content to `NSPasteboard.general`.
- Dismisses the floating panel.
- Simulates `Cmd+V` via `CGEvent` to paste into the frontmost app.
- Requires Accessibility permission.

### ContentClassifier

Classification priority order:
1. URL regex match → `.link`
2. Code heuristics (brackets, indentation, language keywords like `func`, `class`, `import`, `def`, `const`, `var`, `let`; minimum 2 signals required) → `.code`
3. Otherwise → `.text`

If a text block contains both URLs and code patterns, code takes priority (URLs inside code are common).

## App Lifecycle & Scene Configuration

```swift
@main
struct PasteFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar icon with dropdown
        MenuBarExtra("PasteFlow", image: "MenuBarIcon") {
            Button("Open PasteFlow") { appDelegate.togglePanel() }
            Divider()
            Button("Settings...") { appDelegate.openSettings() }
            Button("Quit PasteFlow") { NSApplication.shared.terminate(nil) }
        }

        // Settings window (opened via menu bar or Cmd+,)
        Settings {
            SettingsView()
        }
    }
}
```

- **No `WindowGroup`** — the app has no main window. `LSUIElement = true` hides it from the Dock.
- **`AppDelegate`** manages the `FloatingPanel` (NSPanel) lifecycle: creation, show/hide, positioning.
- **`MenuBarExtra`** provides the menu bar icon and dropdown.
- **`Settings` scene** provides the settings window, automatically wired to the app's "Settings..." menu action.

## UI Structure

```
FloatingPanel (NSPanel subclass — AppKit, managed by AppDelegate)
 └─ PopoverView (SwiftUI, hosted via NSHostingView)
     ├─ SearchBarView          — text field + "Cmd+Shift+V" hint
     ├─ FilterRowView          — pills: All, Text, Link, Code, Image
     ├─ HStack
     │   ├─ ClipListView       — LazyVStack in ScrollView (340pt wide)
     │   └─ DetailPanelView    — preview, metadata, Paste/Delete (220pt wide)
     └─ FooterView             — item count
```

### FloatingPanel (NSPanel)

The only AppKit component. Required for:
- Floating window that appears on hotkey without stealing focus until interaction.
- Dismissing on Esc or click-outside.
- Proper key window behavior for keyboard navigation.

All inner views are pure SwiftUI hosted via `NSHostingView`.

### PopoverView (560 × 456pt, from Figma)

**SearchBarView:**
- Search icon (SF Symbol `magnifyingglass`) + text field + "Cmd+Shift+V" shortcut hint.
- Filters `AppState.clipboardItems` as the user types.

**FilterRowView:**
- Pill-shaped buttons: All, Text, Link, Code, Image.
- Active pill has filled background (`#EEEDFE`), inactive has border only (`#CECBF6`).
- Text color `#3C3489` for all pills.
- Sets `AppState.activeFilter`.

**ClipListView:**
- `LazyVStack` inside a `ScrollView` for efficient rendering of large lists.
- Each row shows: type icon (SF Symbols), content preview (truncated), metadata (time ago, char count or domain), keyboard shortcut label (`Cmd+1` through `Cmd+9`).
- Selected row has blue highlight (`#E6F1FB`), selected text color `#185FA5`.
- Default row has white background, text color `#1A1A1A`, metadata `#999`.
- Arrow keys move selection, Enter triggers paste.
- `Cmd+1` through `Cmd+9` directly select and paste the Nth item.
- Loads more items on scroll (pagination via `StorageService.fetchItems`).

**DetailPanelView:**
- "PREVIEW" label (bold, `#666`).
- Content preview block: code/text in a rounded box (`#F5F5F3` background), images as thumbnail.
- Metadata: content type, character count/image size, time copied, source app.
- Action buttons: Paste (`#EEEDFE` filled) and Delete (border only). No Pin in MVP.
- Image data loaded on demand only when the detail panel displays an image item.

**FooterView:**
- Item count display (e.g., "24 items").
- No pinned count in MVP.

### Time Display Format

Relative time using `RelativeDateTimeFormatter` with `.abbreviated` style:
- Under 1 minute: "just now"
- Minutes/hours/days: "3m ago", "2h ago", "5d ago"
- Beyond 7 days: short date (e.g., "Mar 15")

### Keyboard Interaction

| Key | Action |
|---|---|
| `Cmd+Shift+V` | Toggle floating panel |
| `↑` / `↓` | Navigate clipboard list |
| `Enter` | Paste selected item (direct paste into frontmost app) |
| `Esc` | Dismiss panel |
| `Cmd+1` – `Cmd+9` | Quick paste Nth item |
| Type any text | Focus search field and filter |

### Menu Bar

`MenuBarExtra` with the custom MenuBarIcon asset. Dropdown contains:
- "Open PasteFlow" (opens floating panel)
- Separator
- "Settings..."
- "Quit PasteFlow"

## Settings

Accessible from menu bar dropdown. Uses SwiftUI `Settings` scene.

| Section | Setting | Control | Default |
|---|---|---|---|
| General | Launch at login | Toggle | Off |
| General | Global hotkey | Display only | Cmd+Shift+V |
| Storage | Retention period | Picker: 7, 14, 30, 60, 90 days | 30 days |
| Storage | Clear all history | Button with confirmation | — |
| About | Version info | Label | — |
| About | GitHub link | Link | — |

Stored via `UserDefaults`.

## Permissions

### Accessibility Permission Flow

1. On first launch, check `AXIsProcessTrusted()`.
2. If not granted, show an explanation dialog: "PasteFlow needs Accessibility access to paste items into your apps. Without it, you can still copy items from history, but automatic pasting won't work."
3. Offer a button to open System Settings > Privacy & Security > Accessibility.
4. **Fallback behavior if denied:** Paste simulation is disabled. Selecting an item copies it to the clipboard, and the user must manually `Cmd+V`. A subtle indicator in the footer shows "Accessibility: off — manual paste mode".
5. Re-check `AXIsProcessTrusted()` each time the panel is shown, so the app detects when the user grants permission later.

## Error Handling

- Storage errors (write failures, disk full) are logged via `os_log` and surface a transient message in the footer area (e.g., "Failed to save — disk full").
- Database corruption: on startup, if the database fails to open, attempt a fresh database and log the error. History is lost but the app remains functional.
- Image file read failures (missing file on disk): show a placeholder in the detail panel, log the error.

## Project Structure

```
PasteFlow/
  App/            — PasteFlowApp.swift, AppDelegate.swift
  Models/         — ClipboardItem.swift, ClipboardItemRecord.swift,
                    ContentType.swift, ImageFormat.swift
  State/          — AppState.swift
  Services/       — ClipboardMonitor.swift, StorageService.swift,
                    HotkeyService.swift, PasteSimulator.swift
  Views/          — PopoverView.swift, SearchBarView.swift, FilterRowView.swift,
                    ClipListView.swift, ClipRowView.swift, DetailPanelView.swift,
                    FooterView.swift, SettingsView.swift, FloatingPanel.swift
  Utilities/      — ContentClassifier.swift
```

## Out of Scope (Post-MVP)

- Pinning items (exempt from expiry)
- File clipboard type
- Full-text search (FTS5)
- Customizable hotkey
- iCloud sync
- Snippet/template system
- Image size limits or compression
- Drag and drop from clip list
