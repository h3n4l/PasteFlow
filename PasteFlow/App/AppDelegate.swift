import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel?
    // Initialized eagerly so it's available when SwiftUI evaluates the Settings scene
    lazy var appState: AppState = {
        let storage = try! createStorage()
        return AppState(storage: storage)
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let state = appState

            let popoverView = PopoverView(appState: state) { [weak self] in
                self?.panel?.hidePanel()
            }
            let hostingView = NSHostingView(rootView: popoverView)
            hostingView.frame = NSRect(x: 0, y: 0, width: 560, height: 456)
            let panel = FloatingPanel(contentView: hostingView)
            self.panel = panel

            // Wire up keyboard shortcuts on the panel
            panel.onArrowUp = { [weak state] in state?.selectPrevious() }
            panel.onArrowDown = { [weak state] in state?.selectNext() }
            panel.onEnter = { [weak self, weak state] in
                if let item = state?.selectedItem {
                    self?.panel?.hidePanel()
                    state?.isPanelVisible = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        state?.pasteItem(item)
                    }
                }
            }
            panel.onEsc = { [weak self] in
                self?.panel?.hidePanel()
                self?.appState.isPanelVisible = false
            }
            panel.onCmdNumber = { [weak self, weak state] num in
                let index = num - 1
                if let items = state?.filteredItems,
                   index >= 0, index < items.count {
                    self?.panel?.hidePanel()
                    state?.isPanelVisible = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        state?.pasteItem(items[index])
                    }
                }
            }

            panel.onTab = { [weak state] in state?.cycleFilter() }

            state.hotkeyService.onHotkeyPressed = { [weak self] in self?.togglePanel() }
            state.hotkeyService.register()
            state.clipboardMonitor.start()
            state.setupMonitorCallback()

            if !PasteSimulator.isAccessibilityGranted {
                showAccessibilityDialog()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "PasteFlow Failed to Start"
            alert.informativeText = "Could not initialize storage: \(error.localizedDescription)"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func togglePanel() {
        panel?.toggle()
        let visible = panel?.isVisible == true
        appState.isPanelVisible = visible
        if visible {
            appState.reloadItems()
            appState.isAccessibilityGranted = PasteSimulator.isAccessibilityGranted
        }
    }

    /// Show dock icon, activate app, and watch for settings window close.
    func showSettings() {
        // Switch to regular app (shows dock icon)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Watch for the settings window to close
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    @objc private func windowWillClose(_ notification: Notification) {
        // Check if any visible windows remain (besides the floating panel)
        DispatchQueue.main.async { [weak self] in
            let hasVisibleWindows = NSApp.windows.contains { window in
                window.isVisible && !(window is FloatingPanel) && window.className != "NSStatusBarWindow"
            }
            if !hasVisibleWindows {
                // No more windows — hide dock icon
                NSApp.setActivationPolicy(.accessory)
                NotificationCenter.default.removeObserver(
                    self as Any,
                    name: NSWindow.willCloseNotification,
                    object: nil
                )
            }
        }
    }

    private func createStorage() throws -> StorageService {
        do { return try StorageService() }
        catch {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dbPath = appSupport.appendingPathComponent("PasteFlow/clipboard.db")
            try? FileManager.default.removeItem(at: dbPath)
            return try StorageService()
        }
    }

    private func showAccessibilityDialog() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Access Needed"
        alert.informativeText = "PasteFlow needs Accessibility access to paste items into your apps. Without it, you can still copy items from history, but automatic pasting won't work."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn { PasteSimulator.requestAccessibility() }
    }
}
