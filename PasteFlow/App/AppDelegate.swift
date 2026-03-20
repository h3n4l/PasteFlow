import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel?
    var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let storage = try createStorage()
            let state = AppState(storage: storage)
            self.appState = state

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

            if !PasteSimulator.isAccessibilityGranted { showAccessibilityDialog() }
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
        if panel?.isVisible == true {
            appState?.reloadItems()
            appState?.objectWillChange.send()
        }
    }

    func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
