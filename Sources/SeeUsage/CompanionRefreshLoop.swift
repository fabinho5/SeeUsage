import Foundation

/// A single cancellable loop: no overlapping checks, and no polling while the companion is hidden.
@MainActor
final class CompanionRefreshLoop {
    nonisolated static let interval: Duration = .seconds(300)
    private var task: Task<Void, Never>?

    init(interval: Duration = CompanionRefreshLoop.interval, check: @escaping @MainActor () async -> Void) {
        task = Task {
            while !Task.isCancelled {
                let started = ContinuousClock.now
                await check()
                guard !Task.isCancelled else { return }
                // Keep the five-minute cadence measured from the start of a check.
                let remaining = interval - started.duration(to: ContinuousClock.now)
                do { try await Task.sleep(for: max(.zero, remaining)) }
                catch { return }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    deinit { task?.cancel() }
}
