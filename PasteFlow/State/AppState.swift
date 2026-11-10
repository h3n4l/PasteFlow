import Combine
import Foundation
import os.log

final class AppState: ObservableObject {
    @Published var clipboardItems: [ClipboardItem] = []
    /// The item shown in the detail pane. Setting it directly makes the panel jump there;
    /// `select(_:)`, `selectNext()` and `selectPrevious()` make it glide.
    @Published var selectedItem: ClipboardItem?
    /// Goes up each time the user moves the selection. The panel animates a selection change
    /// only when this changes with it, so the list resetting the selection does not animate.
    @Published private(set) var selectionMoves = 0
    /// Goes up each time the list changes in a way the panel should animate: a delete, a filter
    /// change or a search. Reloads without it, like the one each time the panel opens, appear at once.
    @Published private(set) var listChanges = 0
    /// The item being pasted, from the moment it is chosen until the panel has closed.
    @Published var pastingItemID: UUID?
    @Published var searchText: String = ""
    @Published var activeFilter: ContentType?
    @Published var totalItemCount: Int = 0
    @Published var statusMessage: String?
    @Published var isPanelVisible: Bool = false
    @Published var appearanceMode: AppearanceMode = {
        if let raw = UserDefaults.standard.string(forKey: "appearanceMode"),
           let mode = AppearanceMode(rawValue: raw) {
            return mode
        }
        return .system
    }() {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode")
        }
    }
    @Published var isAccessibilityGranted: Bool = PasteSimulator.isAccessibilityGranted

    #if ENABLE_AUTO_UPDATE
    @Published var updateService: UpdateService? {
        didSet {
            updateCancellable = updateService?.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
        }
    }
    private var updateCancellable: AnyCancellable?
    #endif

    let storage: StorageService
    let clipboardMonitor: ClipboardMonitor
    let hotkeyService: HotkeyService

    private let pageSize = 50
    private var hasMoreItems = true
    private let logger = Logger(subsystem: "com.github.h3n4l.PasteFlow", category: "AppState")
    private var searchDebounce: AnyCancellable?
    private var cleanupTimer: Timer?

    init(storage: StorageService) {
        self.storage = storage
        self.hotkeyService = HotkeyService()

        // Create monitor with a placeholder callback; setupMonitorCallback() wires up the real one.
        // Since onNewItem is a let, we capture a weak reference indirectly via a wrapper.
        let reloadRef = ReloadRef()
        self.clipboardMonitor = ClipboardMonitor(storage: storage) { _ in
            reloadRef.reload?()
        }

        reloadItems()
        cleanupExpired()

        // Now that self is fully initialized, wire up the reload ref
        reloadRef.reload = { [weak self] in
            self?.reloadItems()
        }

        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            self?.cleanupExpired()
        }
    }

    func setupMonitorCallback() {
        // Set up debounced search
        searchDebounce = $searchText
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.reloadItems(animated: true)
            }
    }

    var filteredItems: [ClipboardItem] { clipboardItems }

    /// Loads the first page of items for the current filter and search.
    /// Pass `animated` when the user caused the change while looking at the list.
    func reloadItems(animated: Bool = false) {
        do {
            clipboardItems = try storage.fetchItems(
                filter: activeFilter,
                search: searchText.isEmpty ? nil : searchText,
                limit: pageSize, offset: 0
            )
            totalItemCount = try storage.itemCount(filter: activeFilter)
            hasMoreItems = clipboardItems.count < totalItemCount
            if selectedItem == nil || !clipboardItems.contains(where: { $0.id == selectedItem?.id }) {
                selectedItem = clipboardItems.first
            }
            if animated { listChanges += 1 }
        } catch {
            logger.error("Failed to reload items: \(error.localizedDescription)")
            statusMessage = "Failed to load clipboard history"
        }
    }

    func loadMoreItems() {
        appendItems(limit: pageSize)
    }

    /// Loads up to `limit` more items after the ones already in the list.
    private func appendItems(limit: Int) {
        guard hasMoreItems else { return }
        do {
            let moreItems = try storage.fetchItems(
                filter: activeFilter,
                search: searchText.isEmpty ? nil : searchText,
                limit: limit, offset: clipboardItems.count
            )
            clipboardItems.append(contentsOf: moreItems)
            hasMoreItems = clipboardItems.count < totalItemCount
        } catch {
            logger.error("Failed to load more items: \(error.localizedDescription)")
        }
    }

    func setFilter(_ filter: ContentType?) {
        activeFilter = filter
        reloadItems(animated: true)
    }

    private let filterOrder: [ContentType?] = [nil, .text, .link, .code, .image, .file]

    func cycleFilter() {
        let currentIndex = filterOrder.firstIndex(where: { $0 == activeFilter }) ?? 0
        let nextIndex = (currentIndex + 1) % filterOrder.count
        setFilter(filterOrder[nextIndex])
    }

    func deleteItem(_ item: ClipboardItem) {
        do {
            try storage.delete(item.id)
            guard let index = clipboardItems.firstIndex(where: { $0.id == item.id }) else {
                reloadItems(animated: true)
                return
            }
            // Take the item out of the loaded list rather than reloading, so the list keeps its place.
            clipboardItems.remove(at: index)
            if selectedItem?.id == item.id {
                // The selection stays where it was: on the item that moved into the deleted one's place.
                selectedItem = index < clipboardItems.count ? clipboardItems[index] : clipboardItems.last
            }
            totalItemCount = max(totalItemCount - 1, 0)
            // Load one item in its place. Otherwise deleting again and again would empty the list
            // while older items are still stored: the row that triggers loading more has already appeared.
            appendItems(limit: 1)
            listChanges += 1
        } catch {
            logger.error("Failed to delete item: \(error.localizedDescription)")
            statusMessage = "Failed to delete item"
        }
    }

    func pasteItem(_ item: ClipboardItem) {
        PasteSimulator.paste(item, clipboardMonitor: clipboardMonitor)
    }

    func copyPathItem(_ item: ClipboardItem) {
        PasteSimulator.copyPath(item, clipboardMonitor: clipboardMonitor)
    }

    /// Selects an item the user picked, so the panel glides to it.
    func select(_ item: ClipboardItem) {
        guard selectedItem?.id != item.id else { return }
        selectedItem = item
        selectionMoves += 1
    }

    func selectNext() {
        guard !clipboardItems.isEmpty else { return }
        if let current = selectedItem,
           let index = clipboardItems.firstIndex(where: { $0.id == current.id }),
           index + 1 < clipboardItems.count {
            select(clipboardItems[index + 1])
        }
    }

    func selectPrevious() {
        guard !clipboardItems.isEmpty else { return }
        if let current = selectedItem,
           let index = clipboardItems.firstIndex(where: { $0.id == current.id }),
           index > 0 {
            select(clipboardItems[index - 1])
        }
    }

    private func cleanupExpired() {
        let retentionDays = UserDefaults.standard.integer(forKey: "retentionDays")
        let days = retentionDays > 0 ? retentionDays : 30
        do { try storage.deleteExpired(olderThan: days) }
        catch { logger.error("Failed to clean expired items: \(error.localizedDescription)") }
    }
}

/// Helper class to allow capturing a mutable reload closure in ClipboardMonitor's immutable callback.
private class ReloadRef {
    var reload: (() -> Void)?
}
