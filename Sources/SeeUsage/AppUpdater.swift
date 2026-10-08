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
    static let shared = AppUpdater(backend: productionBackend())
    static let releasesURL = URL(string: "https://github.com/fabinho5/SeeUsage/releases")!

    @Published private(set) var canCheckForUpdates = true
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var errorMessage: String?
    var supportsInAppUpdates: Bool { backend != nil }

    private let backend: AppUpdateBackend?
    private let openReleases: @MainActor () -> Void
    private var started = false

    init(backend: AppUpdateBackend?, openReleases: @escaping @MainActor () -> Void = {
        NSWorkspace.shared.open(AppUpdater.releasesURL)
    }) {
        self.backend = backend
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

    func checkForUpdates() {
        guard canCheckForUpdates, errorMessage == nil else { return }
        if let backend {
            backend.checkForUpdates()
        } else {
            openReleases()
        }
    }

    private func synchronizeState() {
        canCheckForUpdates = errorMessage == nil && (backend?.canCheckForUpdates ?? true)
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
