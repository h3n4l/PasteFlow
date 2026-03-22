import AppKit
import SwiftUI

final class FloatingPanel: NSPanel {
    var onArrowUp: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onEnter: (() -> Void)?
    var onEsc: (() -> Void)?
    var onCmdNumber: ((Int) -> Void)?
    var onTab: (() -> Void)?

    private var localMonitor: Any?

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
        // Default to system appearance; updated by updateAppearance()
    }

    func updateAppearance(_ mode: AppearanceMode) {
        switch mode {
        case .system:
            self.appearance = nil
        case .light:
            self.appearance = NSAppearance(named: .aqua)
        case .dark:
            self.appearance = NSAppearance(named: .darkAqua)
        }
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
        installKeyMonitor()
        makeKeyAndOrderFront(nil)
    }

    func hidePanel() {
        removeKeyMonitor()
        orderOut(nil)
    }

    func toggle() {
        if isVisible { hidePanel() } else { showPanel() }
    }

    override func cancelOperation(_ sender: Any?) { hidePanel() }
    override func resignKey() { super.resignKey(); hidePanel() }

    // MARK: - Key Event Monitor

    /// Intercepts key events before any view (including TextField) handles them.
    private func installKeyMonitor() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isVisible else { return event }
            return self.handleKeyEvent(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    /// Returns true if the event was handled (consumed).
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Cmd+1 through Cmd+9
        if event.modifierFlags.contains(.command) {
            if let chars = event.charactersIgnoringModifiers,
               let num = Int(chars), num >= 1, num <= 9 {
                onCmdNumber?(num)
                return true
            }
        }

        switch event.keyCode {
        case 126: // Up arrow
            onArrowUp?()
            return true
        case 125: // Down arrow
            onArrowDown?()
            return true
        case 36: // Return/Enter
            onEnter?()
            return true
        case 48: // Tab
            onTab?()
            return true
        case 53: // Esc
            onEsc?()
            return true
        default:
            return false // Let TextField and other views handle it
        }
    }

    deinit {
        removeKeyMonitor()
    }
}
