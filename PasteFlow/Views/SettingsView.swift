import ServiceManagement
import SwiftUI

private let settingsLabelWidth: CGFloat = 120

struct SettingsRow<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: settingsLabelWidth, alignment: .trailing)
            content
            Spacer()
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("retentionDays") private var retentionDays: Int = 30
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @State private var showClearConfirmation = false
    #if ENABLE_AUTO_UPDATE
    @State private var showUpdateConfirmation = false
    #endif
    private let retentionOptions = [7, 14, 30, 60, 90]

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gear") }
            storageTab.tabItem { Label("Storage", systemImage: "internaldrive") }
            healthCheckTab.tabItem { Label("Health", systemImage: "stethoscope") }
            aboutTab.tabItem { Label("About", systemImage: "info.circle") }
        }.frame(width: 480, height: 340)
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsRow("Appearance") {
                Picker("", selection: $appState.appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
            }

            SettingsRow("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox)
                    .onChange(of: launchAtLogin) { newValue in
                        do {
                            if newValue { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch { launchAtLogin = !newValue }
                    }
            }

            SettingsRow("Global Hotkey") {
                Text("Cmd+Shift+V")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
            }

            Spacer()
        }.padding(.top, 20).padding(.horizontal, 24)
    }

    private var storageTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsRow("Retention") {
                Picker("", selection: $retentionDays) {
                    ForEach(retentionOptions, id: \.self) { Text("\($0) days").tag($0) }
                }
                .labelsHidden()
                .frame(width: 120)
            }

            SettingsRow("History") {
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
            }

            Spacer()
        }.padding(.top, 20).padding(.horizontal, 24)
    }

    private var healthCheckTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsRow("Data Size") {
                Text(ByteCountFormatter.string(
                    fromByteCount: appState.storage.dataSize(),
                    countStyle: .file
                ))
            }

            SettingsRow("Accessibility") {
                if PasteSimulator.isAccessibilityGranted {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Granted")
                    }
                } else {
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text("Not granted")
                        }
                        Button("Open Settings") {
                            PasteSimulator.requestAccessibility()
                        }
                    }
                }
            }

            Spacer()
        }.padding(.top, 20).padding(.horizontal, 24)
    }

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 64, height: 64)
            Text("PasteFlow").font(.headline)
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                .foregroundColor(.secondary)
            Link("GitHub", destination: URL(string: "https://github.com/h3n4l/PasteFlow")!)

            #if ENABLE_AUTO_UPDATE
            Divider().padding(.horizontal, 40)
            updateSection
            #endif
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    #if ENABLE_AUTO_UPDATE
    @ViewBuilder
    private var updateSection: some View {
        if let updateService = appState.updateService {
            // Error is checked early so it's not hidden behind stale downloading/checking state
            if let error = updateService.error {
                VStack(spacing: 6) {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.callout)
                    Button("Retry") {
                        updateService.checkForUpdates()
                    }
                }
            } else if updateService.isInstalling {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Installing update...")
                }
            } else if updateService.isDownloading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Downloading update...")
                }
            } else if updateService.isChecking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking for updates...")
                }
            } else if updateService.downloadReady, let version = updateService.newVersion {
                VStack(spacing: 6) {
                    Text("PasteFlow \(version) is available")
                        .foregroundColor(.secondary)
                        .font(.callout)
                    Button("Update Now") {
                        showUpdateConfirmation = true
                    }
                    .alert("Update Available", isPresented: $showUpdateConfirmation) {
                        Button("Update Now") {
                            updateService.installUpdate()
                        }
                        Button("Later", role: .cancel) {}
                    } message: {
                        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
                        Text("PasteFlow \(version) is available. You're running v\(current). The app will restart after updating.")
                    }
                }
            } else if updateService.updateAvailable, let version = updateService.newVersion {
                VStack(spacing: 6) {
                    Text("PasteFlow \(version) is available, preparing download...")
                        .foregroundColor(.secondary)
                        .font(.callout)
                }
            } else if updateService.isUpToDate {
                Text("You're running the latest version")
                    .foregroundColor(.secondary)
                    .font(.callout)
            } else {
                Button("Check for Updates") {
                    updateService.checkForUpdates()
                }
            }
        }
    }
    #endif
}
