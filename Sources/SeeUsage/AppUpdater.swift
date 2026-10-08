import AppKit
import Combine
#if ENABLE_SPARKLE
import Sparkle
#endif

/// Kept separate from quota polling: refreshes never initiate software installs.
@MainActor
protocol AppUpdateBackend: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var canCheckForUpdates: Bool { get }
    var stateChanged: (() -> Void)? { get set }
    func start() throws
    func checkInBackground()
    func checkForUpdates()
}

@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater(backend: productionBackend(), checkAvailability: productionAvailabilityCheck())
    static let releasesURL = URL(string: "https://github.com/fabinho5/SeeUsage/releases")!

    @Published private(set) var canCheckForUpdates = true
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var noticeMessage: String?
    @Published private(set) var availableReleaseURL: URL?
    var supportsInAppUpdates: Bool { backend != nil }

    private let backend: AppUpdateBackend?
    private let checkAvailability: (() async throws -> AppUpdateAvailability)?
    private let openReleases: @MainActor () -> Void
    private var started = false
    private var checkingAvailability = false

    init(backend: AppUpdateBackend?, checkAvailability: (() async throws -> AppUpdateAvailability)? = nil,
         openReleases: @escaping @MainActor () -> Void = {
        NSWorkspace.shared.open(AppUpdater.releasesURL)
    }) {
        self.backend = backend
        self.checkAvailability = checkAvailability
        self.openReleases = openReleases
        backend?.stateChanged = { [weak self] in self?.synchronizeState() }
        synchronizeState()
    }

    func start() {
        guard !started else { return }
        started = true
        guard let backend else { return }
        do {
            try backend.start()
            synchronizeState()
            // Sparkle schedules subsequent checks; only request this at launch.
            if backend.automaticallyChecksForUpdates { backend.checkInBackground() }
        } catch {
            errorMessage = "Updates could not start: \(error.localizedDescription)"
            canCheckForUpdates = false
        }
    }

    func setAutomaticChecks(_ enabled: Bool) {
        backend?.automaticallyChecksForUpdates = enabled
        synchronizeState()
    }

    @discardableResult
    func checkForUpdates() -> Task<Void, Never>? {
        guard canCheckForUpdates, errorMessage == nil else { return nil }
        guard let backend else {
            openReleases()
            return nil
        }
        noticeMessage = nil
        availableReleaseURL = nil
        guard let checkAvailability else {
            backend.checkForUpdates()
            return nil
        }
        checkingAvailability = true
        noticeMessage = "Checking for updates…"
        synchronizeState()
        return Task { @MainActor in
            defer { checkingAvailability = false; synchronizeState() }
            do {
                switch try await checkAvailability() {
                case .feedAvailable:
                    noticeMessage = nil
                    backend.checkForUpdates()
                case .upToDate:
                    noticeMessage = "You’re up to date."
                case .notPublished:
                    noticeMessage = "No updates have been published yet."
                case .manualRelease(let version, let url):
                    noticeMessage = "Version \(version) is available on GitHub. In-app updates are not available for that release."
                    availableReleaseURL = url
                }
            } catch {
                noticeMessage = "Couldn’t check for updates. \(error.localizedDescription) Try again later."
            }
        }
    }

    private func synchronizeState() {
        canCheckForUpdates = !checkingAvailability && errorMessage == nil && (backend?.canCheckForUpdates ?? true)
        automaticallyChecksForUpdates = backend?.automaticallyChecksForUpdates ?? false
    }

    private static func productionBackend() -> AppUpdateBackend? {
        #if ENABLE_SPARKLE
        // Unbundled SwiftPM CLI/debug binaries have no update configuration.
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") is String,
              Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") is String else { return nil }
        return SparkleUpdateBackend()
        #else
        return nil
        #endif
    }

    private static func productionAvailabilityCheck() -> (() async throws -> AppUpdateAvailability)? {
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let feedURL = URL(string: feed), feedURL.host == "github.com",
              let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return nil }
        let parts = feedURL.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return nil }
        let checker = ReleaseAvailabilityChecker(feedURL: feedURL, repository: parts.prefix(2).joined(separator: "/"),
                                                currentVersion: version)
        return { try await checker.check() }
    }
}

#if ENABLE_SPARKLE
@MainActor
private final class SparkleUpdateBackend: AppUpdateBackend {
    private let controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil
    )
    private var observations: Set<AnyCancellable> = []
    var stateChanged: (() -> Void)?

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    init() {
        controller.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] _ in self?.stateChanged?() }
            .store(in: &observations)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak self] _ in self?.stateChanged?() }
            .store(in: &observations)
    }

    func start() throws { try controller.updater.start() }
    func checkInBackground() { controller.updater.checkForUpdatesInBackground() }
    func checkForUpdates() { controller.checkForUpdates(nil) }
}
#endif
