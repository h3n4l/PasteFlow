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

        #if !DEBUG
        guard isAccessibilityGranted else {
            logger.info("Accessibility not granted — copied to clipboard only (manual paste mode)")
            return
        }
        #endif

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { simulateCmdV() }
    }

    private static func copyToPasteboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.content {
        case .text(let text):
            pasteboard.setString(text, forType: .string)
        case .image(let data, let format):
            pasteboard.setData(data, forType: pasteboardType(for: format))
        }
    }

    private static func pasteboardType(for format: ImageFormat) -> NSPasteboard.PasteboardType {
        switch format {
        case .png: return .png
        case .tiff: return .tiff
        case .jpeg: return NSPasteboard.PasteboardType("public.jpeg")
        case .gif: return NSPasteboard.PasteboardType("com.compuserve.gif")
        case .bmp: return NSPasteboard.PasteboardType("com.microsoft.bmp")
        case .pdf: return .pdf
        }
    }

    private static func simulateCmdV() {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else {
            logger.error("Failed to create CGEvent for paste simulation")
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
