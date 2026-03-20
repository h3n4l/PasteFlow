import AppKit
import Foundation
import os.log

final class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int
    private let storage: StorageService
    private let onNewItem: (ClipboardItem) -> Void
    private let logger = Logger(subsystem: "com.github.h3n4l.PasteFlow", category: "ClipboardMonitor")

    var suppressNextChange = false

    init(storage: StorageService, onNewItem: @escaping (ClipboardItem) -> Void) {
        self.storage = storage
        self.onNewItem = onNewItem
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkPasteboard() {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        if suppressNextChange {
            suppressNextChange = false
            return
        }

        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName

        if let item = readImage(from: pasteboard, sourceApp: sourceApp) {
            saveAndNotify(item)
        } else if let item = readText(from: pasteboard, sourceApp: sourceApp) {
            saveAndNotify(item)
        }
    }

    private func readText(from pasteboard: NSPasteboard, sourceApp: String?) -> ClipboardItem? {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return nil }
        let contentType = ContentClassifier.classify(text)
        return ClipboardItem(content: .text(text), sourceApp: sourceApp, contentType: contentType)
    }

    private func readImage(from pasteboard: NSPasteboard, sourceApp: String?) -> ClipboardItem? {
        let typeFormatMap: [(NSPasteboard.PasteboardType, ImageFormat)] = [
            (.png, .png),
            (.tiff, .tiff),
        ]
        for (pasteboardType, format) in typeFormatMap {
            if let data = pasteboard.data(forType: pasteboardType) {
                return ClipboardItem(content: .image(data, format), sourceApp: sourceApp, contentType: .image)
            }
        }
        if let data = pasteboard.data(forType: .pdf) {
            return ClipboardItem(content: .image(data, .pdf), sourceApp: sourceApp, contentType: .image)
        }
        return nil
    }

    private func saveAndNotify(_ item: ClipboardItem) {
        do {
            try storage.save(item)
            DispatchQueue.main.async { self.onNewItem(item) }
        } catch {
            logger.error("Failed to save clipboard item: \(error.localizedDescription)")
        }
    }
}
