import SwiftUI

@main
struct PasteFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("PasteFlow", image: "MenuBarIcon") {
            Button("Open PasteFlow") { appDelegate.togglePanel() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            Divider()
            Button("Settings...") { appDelegate.openSettings() }
                .keyboardShortcut(",", modifiers: .command)
            Button("Quit PasteFlow") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
        Settings {
            if let appState = appDelegate.appState {
                SettingsView().environmentObject(appState)
            } else {
                Text("Loading...").frame(width: 400, height: 250)
            }
        }
    }
}
