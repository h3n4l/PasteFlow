import SwiftUI

@main
struct PasteFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("PasteFlow", image: "MenuBarIcon") {
            if #available(macOS 14.0, *) {
                MenuBarMenuView14(appDelegate: appDelegate)
            } else {
                MenuBarMenuView13(appDelegate: appDelegate)
            }
        }
        Settings {
            SettingsView().environmentObject(appDelegate.appState)
        }
    }
}

// macOS 14+: use @Environment(\.openSettings)
@available(macOS 14.0, *)
struct MenuBarMenuView14: View {
    let appDelegate: AppDelegate
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Open PasteFlow") { appDelegate.togglePanel() }
            .keyboardShortcut("v", modifiers: [.command, .shift])
        Divider()
        Button("Settings...") {
                appDelegate.showSettings()
                DispatchQueue.main.async {
                    openSettings()
                }
            }
            .keyboardShortcut(",", modifiers: .command)
        Button("Quit PasteFlow") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}

// macOS 13: fallback using sendAction
struct MenuBarMenuView13: View {
    let appDelegate: AppDelegate

    var body: some View {
        Button("Open PasteFlow") { appDelegate.togglePanel() }
            .keyboardShortcut("v", modifiers: [.command, .shift])
        Divider()
        Button("Settings...") {
            appDelegate.showSettings()
            DispatchQueue.main.async {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
        .keyboardShortcut(",", modifiers: .command)
        Button("Quit PasteFlow") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
