import Combine
import Foundation
import os.log

final class AppState: ObservableObject {
    @Published var clipboardItems: [ClipboardItem] = []
    @Published var selectedItem: ClipboardItem?
    @Published var searchText: String = ""
    @Published var activeFilter: ContentType?
    @Published var totalItemCount: Int = 0
    @Published var statusMessage: String?
    @Published var isPanelVisible: Bool = false
    @Published var isAccessibilityGranted: Bool = PasteSimulator.isAccessibilityGranted

    #if ENABLE_AUTO_UPDATE
    @Published var updateService: UpdateService?
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
                self?.reloadItems()
            }
    }

    var filteredItems: [ClipboardItem] { clipboardItems }

    func reloadItems() {
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
        } catch {
            logger.error("Failed to reload items: \(error.localizedDescription)")
            statusMessage = "Failed to load clipboard history"
        }
    }

    func loadMoreItems() {
        guard hasMoreItems else { return }
        do {
            let moreItems = try storage.fetchItems(
                filter: activeFilter,
                search: searchText.isEmpty ? nil : searchText,
                limit: pageSize, offset: clipboardItems.count
            )
            clipboardItems.append(contentsOf: moreItems)
            hasMoreItems = clipboardItems.count < totalItemCount
        } catch {
            logger.error("Failed to load more items: \(error.localizedDescription)")
        }
    }

    func setFilter(_ filter: ContentType?) {
        activeFilter = filter
        reloadItems()
    }

    private let filterOrder: [ContentType?] = [nil, .text, .link, .code, .image]

    func cycleFilter() {
        let currentIndex = filterOrder.firstIndex(where: { $0 == activeFilter }) ?? 0
        let nextIndex = (currentIndex + 1) % filterOrder.count
        setFilter(filterOrder[nextIndex])
    }

    func deleteItem(_ item: ClipboardItem) {
        do {
            try storage.delete(item.id)
            reloadItems()
        } catch {
            logger.error("Failed to delete item: \(error.localizedDescription)")
            statusMessage = "Failed to delete item"
        }
    }

    func pasteItem(_ item: ClipboardItem) {
        PasteSimulator.paste(item, clipboardMonitor: clipboardMonitor)
    }

    func selectNext() {
        guard !clipboardItems.isEmpty else { return }
        if let current = selectedItem,
           let index = clipboardItems.firstIndex(where: { $0.id == current.id }),
           index + 1 < clipboardItems.count {
            selectedItem = clipboardItems[index + 1]
        }
    }

    func selectPrevious() {
        guard !clipboardItems.isEmpty else { return }
        if let current = selectedItem,
           let index = clipboardItems.firstIndex(where: { $0.id == current.id }),
           index > 0 {
            selectedItem = clipboardItems[index - 1]
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
