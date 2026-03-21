import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("retentionDays") private var retentionDays: Int = 30
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @State private var showClearConfirmation = false
    private let retentionOptions = [7, 14, 30, 60, 90]

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gear") }
            storageTab.tabItem { Label("Storage", systemImage: "internaldrive") }
            healthCheckTab.tabItem { Label("Health", systemImage: "stethoscope") }
            aboutTab.tabItem { Label("About", systemImage: "info.circle") }
        }.frame(width: 400, height: 280)
    }

    private var generalTab: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    do {
                        if newValue { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                    } catch { launchAtLogin = !newValue }
                }
            LabeledContent("Global hotkey") {
                Text("Cmd+Shift+V").foregroundColor(.secondary)
            }
        }.padding()
    }

    private var storageTab: some View {
        Form {
            Picker("Keep history for", selection: $retentionDays) {
                ForEach(retentionOptions, id: \.self) { Text("\($0) days").tag($0) }
            }
            Button("Clear All History") { showClearConfirmation = true }
                .alert("Clear All History?", isPresented: $showClearConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Clear", role: .destructive) {
                        do {
                            try appState.storage.deleteExpired(olderThan: 0)
                            appState.reloadItems()
                        } catch {}
                    }
                } message: {
                    Text("This will permanently delete all clipboard history. This cannot be undone.")
                }
        }.padding()
    }

    private var healthCheckTab: some View {
        Form {
            LabeledContent("Data size") {
                Text(ByteCountFormatter.string(
                    fromByteCount: appState.storage.dataSize(),
                    countStyle: .file
                ))
                .foregroundColor(.secondary)
            }

            LabeledContent("Accessibility") {
                if PasteSimulator.isAccessibilityGranted {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Granted")
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text("Not granted")
                                .foregroundColor(.secondary)
                        }
                        Button("Open Settings") {
                            PasteSimulator.requestAccessibility()
                        }
                    }
                }
            }
        }.padding()
    }

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 64, height: 64)
            Text("PasteFlow").font(.headline)
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                .foregroundColor(.secondary)
            Link("GitHub", destination: URL(string: "https://github.com/h3n4l/PasteFlow")!)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
