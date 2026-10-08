import Foundation

/// Pacing compares the current allowance with a linear budget for the window's time left.
/// It needs a reset and duration, rather than inventing historical observations.
struct QuotaPacing: Equatable, Sendable {
    let expectedRemainingPercent: Double
    let balancePercent: Double
    let status: QuotaForecast.Status
    let runsOutAt: Date?
    let referenceDate: Date
    let fullSessionWindowsLeft: Int?

    var text: String {
        switch status {
        case .reserve: return "\(Int(balancePercent.rounded()))% in reserve · Lasts until reset"
        case .deficit:
            let outcome = runsOutAt.map {
                $0 <= referenceDate ? "May run out now" : "Runs out in \(QuotaForecast.duration($0.timeIntervalSince(referenceDate)))"
            }
                ?? "Above planned pace"
            return "\(Int(abs(balancePercent).rounded()))% in deficit · \(outcome)"
        case .onTrack:
            return runsOutAt.map { $0 < referenceDate } == true
                ? "Close to limit · Refresh usage"
                : "On pace · \(balancePercent < 0 ? "Little margin" : "Lasts until reset")"
        case .idle: return "No usage yet · Full allowance"
        case .exhausted: return "Quota exhausted · Waiting for reset"
        case .learning: return "Learning usage"
        }
    }

    var windowText: String? {
        fullSessionWindowsLeft.map { "\($0) window\($0 == 1 ? "" : "s") until reset" }
    }

    var explanation: String {
        "Pacing budget at the latest reading: ~\(Int(expectedRemainingPercent.rounded()))% should remain for the time left. "
            + "Reserve/deficit is the difference from that budget, in percentage points. "
            + "Run-out time assumes the average consumption since this quota window began; it is an estimate."
    }

    static func calculate(for window: UsageWindow, fetchedAt: Date, now: Date) -> QuotaPacing? {
        guard let remaining = window.remainingPercent, remaining.isFinite, (0...100).contains(remaining),
              let reset = window.resetsAt, reset > now, fetchedAt <= now else { return nil }
        let durationMinutes = window.durationMinutes
            ?? (FloatingQuotaPeriod.fiveHours.matches(window) ? 300 : (FloatingQuotaPeriod.weekly.matches(window) ? 10_080 : nil))
        guard let durationMinutes, durationMinutes > 0 else { return nil }
        let duration = Double(durationMinutes) * 60
        let timeLeft = reset.timeIntervalSince(now)
        // Do not infer a cycle beginning from an inconsistent/future deadline.
        guard reset.timeIntervalSince(fetchedAt) <= duration + 60 else { return nil }
        let expected = min(100, max(0, reset.timeIntervalSince(fetchedAt) / duration * 100))
        let balance = remaining - expected
        let elapsedAtReading = max(0, duration - reset.timeIntervalSince(fetchedAt))
        let consumed = 100 - remaining
        let runsOutAt = consumed > 0 && elapsedAtReading >= 300
            ? fetchedAt.addingTimeInterval(remaining / consumed * elapsedAtReading) : nil
        let status: QuotaForecast.Status
        if remaining == 0 { status = .exhausted }
        else if balance > 1 { status = .reserve }
        else if balance < -1 { status = .deficit }
        else { status = .onTrack }
        let fullWindows = FloatingQuotaPeriod.weekly.matches(window) ? Int(floor(timeLeft / 18_000)) : nil
        return QuotaPacing(expectedRemainingPercent: expected, balancePercent: balance, status: status,
                           runsOutAt: runsOutAt, referenceDate: now, fullSessionWindowsLeft: fullWindows)
    }
}
