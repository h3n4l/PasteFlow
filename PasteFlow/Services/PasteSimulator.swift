import AppKit
import Foundation
import os.log

enum PasteSimulator {
    private static let logger = Logger(subsystem: "com.github.h3n4l.PasteFlow", category: "PasteSimulator")

    static var isAccessibilityGranted: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func paste(_ item: ClipboardItem, clipboardMonitor: ClipboardMonitor? = nil) {
        clipboardMonitor?.suppressNextChange = true
        copyToPasteboard(item)

        guard isAccessibilityGranted else {
            logger.info("Accessibility not granted — copied to clipboard only (manual paste mode)")
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { simulateCmdV() }
    }

    static func copyPath(_ item: ClipboardItem, clipboardMonitor: ClipboardMonitor? = nil) {
        guard case .file(let refs) = item.content else { return }
        clipboardMonitor?.suppressNextChange = true
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let paths = refs.map(\.path).joined(separator: "\n")
        pasteboard.setString(paths, forType: .string)
    }

    private static func copyToPasteboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.content {
        case .text(let text):
            pasteboard.setString(text, forType: .string)
        case .image(let data, let format):
            pasteboard.setData(data, forType: pasteboardType(for: format))
        case .file(let refs):
            let urls = refs.map { URL(fileURLWithPath: $0.path) as NSURL }
            pasteboard.writeObjects(urls)
        }
    }

    private static func pasteboardType(for format: ImageFormat) -> NSPasteboard.PasteboardType {
        switch format {
        case .png: return .png
        case .tiff: return .tiff
        case .jpeg: return NSPasteboard.PasteboardType("public.jpeg")
        case .gif: return NSPasteboard.PasteboardType("com.compuserve.gif")
        case .bmp: return NSPasteboard.PasteboardType("com.microsoft.bmp")
        case .webp: return NSPasteboard.PasteboardType("org.webmproject.webp")
        case .heic: return NSPasteboard.PasteboardType("public.heic")
        case .pdf: return .pdf
        }
    }

    private static func simulateCmdV() {
        // Based on Maccy/Clipy's proven approach:
        // - Use .combinedSessionState for better keyboard state tracking
        // - Suppress local events during paste to prevent interference
        // - Post to .cgSessionEventTap (session level, more reliable than .cghidEventTap)
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let vKeyCode: CGKeyCode = 0x09 // V key
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else {
            logger.error("Failed to create CGEvent for paste simulation")
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }
}
