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

        if let item = readFiles(from: pasteboard, sourceApp: sourceApp) {
            saveAndNotify(item)
        } else if let item = readImage(from: pasteboard, sourceApp: sourceApp) {
            saveAndNotify(item)
        } else if let item = readText(from: pasteboard, sourceApp: sourceApp) {
            saveAndNotify(item)
        }
    }

    private static let imageUTIToFormat: [String: ImageFormat] = [
        "public.png": .png,
        "public.jpeg": .jpeg,
        "public.tiff": .tiff,
        "com.compuserve.gif": .gif,
        "com.microsoft.bmp": .bmp,
        "org.webmproject.webp": .webp,
        "public.heic": .heic,
    ]

    private func readFiles(from pasteboard: NSPasteboard, sourceApp: String?) -> ClipboardItem? {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return nil
        }
        let fileURLs = urls.filter { $0.isFileURL }
        guard !fileURLs.isEmpty else { return nil }

        // Single image file: read data from disk and treat as image
        if fileURLs.count == 1,
           let resourceValues = try? fileURLs[0].resourceValues(forKeys: [.typeIdentifierKey]),
           let uti = resourceValues.typeIdentifier,
           let format = Self.imageUTIToFormat[uti],
           let data = try? Data(contentsOf: fileURLs[0]) {
            return ClipboardItem(content: .image(data, format), sourceApp: sourceApp, contentType: .image, sourceFilename: fileURLs[0].lastPathComponent)
        }

        let refs = fileURLs.map { url -> FileReference in
            let name = url.lastPathComponent
            let size: Int64
            let utiType: String
            let utiDescription: String

            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let fileSize = attrs[.size] as? Int64 {
                size = fileSize
            } else {
                size = 0
            }

            if let resourceValues = try? url.resourceValues(forKeys: [.typeIdentifierKey, .localizedTypeDescriptionKey]) {
                utiType = resourceValues.typeIdentifier ?? "public.item"
                utiDescription = resourceValues.localizedTypeDescription ?? "File"
            } else {
                utiType = "public.item"
                utiDescription = "File"
            }

            return FileReference(path: url.path, name: name, size: size,
                                  utiType: utiType, utiDescription: utiDescription)
        }

        return ClipboardItem(content: .file(refs), sourceApp: sourceApp, contentType: .file)
    }

    private func readText(from pasteboard: NSPasteboard, sourceApp: String?) -> ClipboardItem? {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return nil }
        let contentType = ContentClassifier.classify(text)
        return ClipboardItem(content: .text(text), sourceApp: sourceApp, contentType: contentType)
    }

    private func readImage(from pasteboard: NSPasteboard, sourceApp: String?) -> ClipboardItem? {
        let typeFormatMap: [(NSPasteboard.PasteboardType, ImageFormat)] = [
            (.png, .png),
            (NSPasteboard.PasteboardType("public.jpeg"), .jpeg),
            (.tiff, .tiff),
            (NSPasteboard.PasteboardType("com.compuserve.gif"), .gif),
            (NSPasteboard.PasteboardType("com.microsoft.bmp"), .bmp),
            (NSPasteboard.PasteboardType("org.webmproject.webp"), .webp),
            (NSPasteboard.PasteboardType("public.heic"), .heic),
        ]
        for (pasteboardType, format) in typeFormatMap {
            if let data = pasteboard.data(forType: pasteboardType) {
                return ClipboardItem(content: .image(data, format), sourceApp: sourceApp, contentType: .image)
            }
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
