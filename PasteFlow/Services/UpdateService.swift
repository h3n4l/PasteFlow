#if ENABLE_AUTO_UPDATE
import AppUpdater
import Combine
import Foundation
import Version
import os.log

/// Custom release provider that configures the JSON decoder to use tolerant
/// version parsing, so tag names like "v0.0.2" are decoded correctly.
/// Delegates download/asset operations to the default GithubReleaseProvider.
private struct TolerantGithubReleaseProvider: ReleaseProvider {
    private let fallback = GithubReleaseProvider()

    func fetchReleases(owner: String, repo: String, proxy: URLRequestProxy?) async throws -> [Release] {
        let slug = "\(owner)/\(repo)"
        let url = URL(string: "https://api.github.com/repos/\(slug)/releases")!
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.userInfo[.decodingMethod] = DecodingMethod.tolerant
        return try decoder.decode([Release].self, from: data)
    }

    func download(asset: Release.Asset, to saveLocation: URL, proxy: URLRequestProxy?) async throws -> AsyncThrowingStream<DownloadingState, Error> {
        return try await fallback.download(asset: asset, to: saveLocation, proxy: proxy)
    }

    func fetchAssetData(asset: Release.Asset, proxy: URLRequestProxy?) async throws -> Data {
        return try await fallback.fetchAssetData(asset: asset, proxy: proxy)
    }
}

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
        self.updater = AppUpdater(owner: "h3n4l", repo: "PasteFlow", provider: TolerantGithubReleaseProvider())
        // Debug builds are signed with a development certificate that differs
        // from the release build's signature, causing AppUpdater's code signing
        // validation to fail. Skip the check so updates can be tested locally.
        #if DEBUG
        self.updater.skipCodeSignValidation = true
        #endif
        observeUpdaterState()
    }

    private func observeUpdaterState() {
        cancellable = updater.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .none:
                    self.updateAvailable = false
                    self.newVersion = nil
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
        // Reconnect observer in case it was disconnected after a previous failure
        if cancellable == nil {
            observeUpdaterState()
        }

        updater.check(
            success: { [weak self] in
                DispatchQueue.main.async {
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
                }
            },
            fail: { [weak self] err in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isChecking = false
                    // Reset download state — AppUpdater's internal progress timer
                    // may keep pushing .downloading state via Combine even after
                    // failure, so disconnect the observer to prevent it from
                    // overwriting our state, then clear the flags.
                    self.cancellable = nil
                    self.isDownloading = false
                    self.updateAvailable = false
                    // AppUpdater throws .noValidUpdate when no viable asset is found,
                    // and AUError.cancelled when current version >= latest release.
                    let isUpToDateError: Bool = {
                        if let e = err as? AppUpdater.Error, e == .noValidUpdate { return true }
                        if case AUError.cancelled = err { return true }
                        return false
                    }()
                    if isUpToDateError {
                        if !silent {
                            self.isUpToDate = true
                        }
                        self.logger.info("Already up to date")
                    } else {
                        if !silent {
                            self.error = "Update failed: \(err.localizedDescription)"
                        }
                        self.logger.error("Update check failed: \(String(describing: err))")
                    }
                }
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
