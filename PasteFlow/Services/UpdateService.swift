#if ENABLE_AUTO_UPDATE
import AppUpdater
import Combine
import Foundation
import os.log

/// Wraps AppUpdater to expose update state for SwiftUI views.
/// Not annotated @MainActor to match AppState's pattern — all @Published
/// updates happen on main thread via Combine observation of AppUpdater's state.
final class UpdateService: ObservableObject {
    private let updater: AppUpdater
    private let logger = Logger(subsystem: "com.github.h3n4l.PasteFlow", category: "UpdateService")
    private var cancellable: AnyCancellable?

    @Published var updateAvailable = false
    @Published var newVersion: String?
    @Published var isChecking = false
    @Published var isDownloading = false
    @Published var downloadReady = false
    @Published var isInstalling = false
    @Published var isUpToDate = false
    @Published var error: String?

    init() {
        self.updater = AppUpdater(owner: "h3n4l", repo: "PasteFlow")

        // Observe AppUpdater's state transitions via Combine
        cancellable = updater.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .none:
                    self.isDownloading = false
                    self.downloadReady = false
                case .newVersionDetected(let release, _):
                    self.updateAvailable = true
                    self.newVersion = release.tagName.description
                    self.isDownloading = false
                    self.downloadReady = false
                case .downloading(let release, _, _):
                    self.updateAvailable = true
                    self.newVersion = release.tagName.description
                    self.isDownloading = true
                    self.downloadReady = false
                case .downloaded(let release, _, _):
                    self.updateAvailable = true
                    self.newVersion = release.tagName.description
                    self.isDownloading = false
                    self.downloadReady = true
                }
            }
    }

    /// Check for updates. If `silent` is true (launch check), errors are suppressed.
    func checkForUpdates(silent: Bool = false) {
        isChecking = true
        isUpToDate = false
        error = nil

        updater.check(
            success: { [weak self] in
                guard let self else { return }
                self.isChecking = false
                if !self.updateAvailable && !silent {
                    self.isUpToDate = true
                }
                if self.updateAvailable {
                    self.logger.info("Update available: \(self.newVersion ?? "unknown")")
                } else {
                    self.logger.info("Already up to date")
                }
            },
            fail: { [weak self] err in
                guard let self else { return }
                self.isChecking = false
                if !silent {
                    self.error = "Couldn't check for updates. Please check your connection."
                }
                self.logger.error("Update check failed: \(err.localizedDescription)")
            }
        )
    }

    /// Install the downloaded update. Only callable when downloadReady is true.
    /// Replaces the app bundle and relaunches.
    @MainActor
    func installUpdate() {
        guard case .downloaded(_, _, let bundle) = updater.state else {
            error = "Update not ready for installation."
            return
        }

        isInstalling = true
        error = nil

        do {
            try updater.installThrowing(bundle)
            // App will terminate and relaunch — we won't reach here
        } catch {
            self.isInstalling = false
            self.error = "Update failed: \(error.localizedDescription)"
            logger.error("Install failed: \(error.localizedDescription)")
        }
    }
}
#endif
