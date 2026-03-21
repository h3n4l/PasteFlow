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

            state.hotkeyService.onHotkeyPressed = { [weak self] in self?.togglePanel() }
            state.hotkeyService.register()
            state.clipboardMonitor.start()
            state.setupMonitorCallback()

            // Check accessibility — skip in DEBUG since Xcode's debug process
            // has a different identity and AXIsProcessTrusted() returns false
            // even when the app is granted in System Settings.
            #if !DEBUG
            if !PasteSimulator.isAccessibilityGranted {
                showAccessibilityDialog()
            }
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
        panel?.toggle()
        let visible = panel?.isVisible == true
        appState.isPanelVisible = visible
        if visible {
            appState.reloadItems()
            appState.isAccessibilityGranted = PasteSimulator.isAccessibilityGranted
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
