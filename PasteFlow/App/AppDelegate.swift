import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel?
    private var cancellables = Set<AnyCancellable>()
    // Initialized eagerly so it's available when SwiftUI evaluates the Settings scene
    lazy var appState: AppState = {
        let storage = try! createStorage()
        return AppState(storage: storage)
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let state = appState

            let popoverView = PopoverView(appState: state) { [weak self] item in
                self?.pasteAndDismiss(item)
            }
            let panel = FloatingPanel(rootView: popoverView)
            self.panel = panel
            panel.onHide = { [weak state] in state?.isPanelVisible = false }

            panel.updateAppearance(state.appearanceMode)
            state.$appearanceMode
                .receive(on: RunLoop.main)
                .sink { [weak panel] mode in
                    panel?.updateAppearance(mode)
                }
                .store(in: &cancellables)

            // Wire up keyboard shortcuts on the panel
            panel.onArrowUp = { [weak state] in state?.selectPrevious() }
            panel.onArrowDown = { [weak state] in state?.selectNext() }
            panel.onEnter = { [weak self, weak state] in
                if let item = state?.selectedItem { self?.pasteAndDismiss(item) }
            }
            panel.onEsc = { [weak self] in self?.panel?.hidePanel() }
            panel.onCmdNumber = { [weak self, weak state] num in
                let index = num - 1
                if let items = state?.filteredItems,
                   index >= 0, index < items.count {
                    self?.pasteAndDismiss(items[index])
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

            #if ENABLE_AUTO_UPDATE
            let updateService = UpdateService()
            state.updateService = updateService
            updateService.checkForUpdates(silent: true)
            #endif
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
        // A paste is already closing the panel; let it finish.
        guard let panel, appState.pastingItemID == nil else { return }
        panel.toggle()
        let visible = panel.isPresented
        appState.isPanelVisible = visible
        if visible {
            appState.reloadItems()
            appState.selectedItem = appState.clipboardItems.first
            appState.isAccessibilityGranted = PasteSimulator.isAccessibilityGranted
        }
    }

    /// Lights up the item's row to confirm the choice, closes the panel, then pastes the item
    /// into the app underneath.
    private func pasteAndDismiss(_ item: ClipboardItem) {
        // Ignore a second Enter or click while the first paste is still closing the panel.
        guard let panel, panel.isPresented, appState.pastingItemID == nil else { return }
        appState.pastingItemID = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + PanelMotion.pasteFlashDuration) { [weak self] in
            panel.hidePanel {
                guard let self else { return }
                self.appState.pastingItemID = nil
                // The panel is off screen now. Give the app underneath a moment to take the keyboard back.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.appState.pasteItem(item) }
            }
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
