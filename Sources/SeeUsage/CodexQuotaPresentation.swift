import Foundation

enum CodexQuotaPresentation {
    static func isReserve(_ window: UsageWindow) -> Bool {
        ["base_model_inference", "gpt-reserve", "gpt_reserve"].contains(window.scope?.lowercased() ?? "")
    }

    /// Keep the main session/weekly pair together, including when reading older caches.
    static func ordered(_ windows: [UsageWindow]) -> [UsageWindow] {
        windows.enumerated().sorted { left, right in
            let leftRank = rank(left.element), rightRank = rank(right.element)
            if leftRank != rightRank { return leftRank < rightRank }
            let leftDuration = left.element.durationMinutes ?? Int.max
            let rightDuration = right.element.durationMinutes ?? Int.max
            if leftDuration != rightDuration { return leftDuration < rightDuration }
            return left.offset < right.offset
        }.map(\.element)
    }

    private static func rank(_ window: UsageWindow) -> Int {
        if isReserve(window) { return 4 }
        guard window.scope == nil || window.scope?.lowercased() == "codex" else { return 3 }
        if FloatingQuotaPeriod.fiveHours.matches(window) { return 0 }
        if FloatingQuotaPeriod.weekly.matches(window) { return 1 }
        return 2
    }
}
