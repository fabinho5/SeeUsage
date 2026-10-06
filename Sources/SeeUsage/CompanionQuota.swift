import Foundation

enum CompanionLook: String, CaseIterable, Sendable {
    case healthy, worn, critical, unavailable

    init(remainingPercent: Double?) {
        switch remainingPercent {
        case nil: self = .unavailable
        case let value? where value < 15: self = .critical
        case let value? where value < 40: self = .worn
        default: self = .healthy
        }
    }
}

enum CompanionReaction: Equatable, Sendable {
    case none
    case damage(Double)
    case celebrate
}

struct CompanionQuotaReading: Sendable {
    struct ID: Hashable, Sendable {
        let source: String
        let window: String
        let scope: String?
        let durationMinutes: Int?
    }

    let id: ID
    let remainingPercent: Double
    let observedAt: Date
    let resetsAt: Date?

    static func collect(profiles: [UsageProfile], snapshots: [UUID: UsageSnapshot],
                        claudeUsage: ClaudeUsageSnapshot?, now: Date = Date()) -> [Self] {
        var readings: [Self] = []
        for profile in profiles {
            guard let snapshot = snapshots[profile.id], snapshot.error == nil else { continue }
            readings += makeReadings(source: profile.id.uuidString, windows: snapshot.windows,
                                     observedAt: snapshot.fetchedAt, now: now)
        }
        if let claudeUsage {
            readings += makeReadings(source: "claude-code", windows: claudeUsage.windows,
                                     observedAt: claudeUsage.updatedAt, now: now)
        }
        return readings
    }

    private static func makeReadings(source: String, windows: [UsageWindow], observedAt: Date, now: Date) -> [Self] {
        // The companion checks every five minutes; stale cache data must not cause a reaction.
        guard now.timeIntervalSince(observedAt) <= 600, observedAt <= now.addingTimeInterval(60) else { return [] }
        return windows.compactMap { window in
            guard let percent = window.remainingPercent, percent.isFinite,
                  (window.resetsAt ?? .distantFuture) > now else { return nil }
            return Self(id: ID(source: source, window: window.id, scope: window.scope,
                               durationMinutes: window.durationMinutes),
                        remainingPercent: max(0, min(100, percent)), observedAt: observedAt,
                        resetsAt: window.resetsAt)
        }
    }
}

struct CompanionQuotaUpdate: Equatable {
    let look: CompanionLook
    let remainingPercent: Double?
    let reaction: CompanionReaction
}

/// Compares the same profile and quota window, rather than comparing two changing global minima.
struct CompanionQuotaTracker {
    private var previous: [CompanionQuotaReading.ID: CompanionQuotaReading] = [:]

    mutating func update(_ readings: [CompanionQuotaReading], now: Date = Date()) -> CompanionQuotaUpdate {
        var current: [CompanionQuotaReading.ID: CompanionQuotaReading] = [:]
        for reading in readings {
            if let existing = current[reading.id], existing.observedAt >= reading.observedAt { continue }
            current[reading.id] = reading
        }
        var largestLoss = 0.0
        var comparisons = 0
        var recovered = false
        let selectionChanged = Set(current.keys) != Set(previous.keys)

        for (id, reading) in current {
            guard let old = previous[id] else { continue }
            guard reading.observedAt > old.observedAt else {
                // A cache notification or a duplicate refresh is not a new measurement.
                current[id] = old
                continue
            }
            let resetAdvanced: Bool
            if let oldReset = old.resetsAt, let newReset = reading.resetsAt {
                resetAdvanced = newReset.timeIntervalSince(oldReset) > 60
            } else {
                resetAdvanced = false
            }
            if resetAdvanced || (old.resetsAt.map { $0 <= now } ?? false) {
                recovered = true
                continue
            }
            comparisons += 1
            largestLoss = max(largestLoss, old.remainingPercent - reading.remainingPercent)
        }
        previous = current
        let remaining = current.values.map(\.remainingPercent).min()
        let look = CompanionLook(remainingPercent: remaining)

        let reaction: CompanionReaction
        if largestLoss > 0.01 {
            // 5h and weekly windows often reflect the same consumption; do not add them twice.
            reaction = .damage(largestLoss)
        } else if !selectionChanged && (comparisons > 0 || recovered) {
            reaction = .celebrate
        } else {
            reaction = .none
        }
        return CompanionQuotaUpdate(look: look, remainingPercent: remaining, reaction: reaction)
    }
}
