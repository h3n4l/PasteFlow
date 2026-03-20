import AppKit
import SwiftUI

final class FloatingPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 456),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        self.isFloatingPanel = true
        self.level = .floating
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = false
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = false
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.contentView = contentView
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.cornerRadius = 12
        self.contentView?.layer?.masksToBounds = true
    }

    func centerOnScreen() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.midY - frame.height / 2
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    func showPanel() {
        centerOnScreen()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hidePanel() { orderOut(nil) }

    func toggle() {
        if isVisible { hidePanel() } else { showPanel() }
    }

    override func cancelOperation(_ sender: Any?) { hidePanel() }
    override func resignKey() { super.resignKey(); hidePanel() }
}
