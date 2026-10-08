import Foundation
import Observation

// MARK: - Quota Sample Record
public struct QuotaSampleRecord: Codable, Sendable, Identifiable {
    public var id: String { "\(profileID.uuidString)-\(windowID ?? "\(scope ?? "")-\(windowLabel)")" }
    public let timestamp: Date
    public let profileID: UUID
    public let profileName: String
    public let service: String
    public let scope: String?
    public let windowLabel: String
    public let windowID: String?
    public let durationMinutes: Int?
    public let remainingPercent: Double
    public let resetsAt: Date?

    public init(
        timestamp: Date,
        profileID: UUID,
        profileName: String,
        service: String,
        scope: String?,
        windowLabel: String,
        windowID: String? = nil,
        durationMinutes: Int? = nil,
        remainingPercent: Double,
        resetsAt: Date?
    ) {
        self.timestamp = timestamp
        self.profileID = profileID
        self.profileName = profileName
        self.service = service
        self.scope = scope
        self.windowLabel = windowLabel
        self.windowID = windowID
        self.durationMinutes = durationMinutes
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
    }

    public var usedPercent: Double {
        max(0.0, min(100.0, 100.0 - remainingPercent))
    }
}

// MARK: - Quota History Snapshot
public struct QuotaHistorySnapshot: Codable, Sendable, Identifiable {
    public var id: Double { timestamp.timeIntervalSince1970 }
    public let timestamp: Date
    public let records: [QuotaSampleRecord]
}

// MARK: - Analytics Aggregation Models
public struct HourlyConsumption: Identifiable, Sendable {
    public var id: Int { hour }
    public let hour: Int // 0...23
    public let consumptionPercent: Double
    public var hourLabel: String {
        String(format: "%02d:00", hour)
    }
}

public struct DailyConsumption: Identifiable, Sendable {
    public var id: String { "\(dayKey)-\(profileID.uuidString)" }
    public let dayKey: String // "yyyy-MM-dd"
    public let date: Date
    public let profileID: UUID
    public let profileName: String
    public let consumptionPercent: Double

    public var weekdayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    public var shortDateLabel: String {
        Formatters.dayMonthName(date)
    }
}

public struct ProfileUsageSummary: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let service: String
    public let totalConsumption: Double
    public let percentageOfTotal: Double
}

public struct AnalyticsMetrics: Sendable {
    public let totalConsumption7Days: Double
    public let peakHourRange: String
    public let primaryProfileName: String
    public let totalSamplesCount: Int
    public let dailyAverageConsumption: Double
}

// MARK: - Analytics & History Manager
@Observable
@MainActor
public final class AnalyticsManager {
    public static let shared = AnalyticsManager()

    public private(set) var snapshots: [QuotaHistorySnapshot] = []
    public private(set) var resetEvents: [ResetEvent] = []
    public private(set) var lastRecordedAt: Date?

    public static var historyFileURL: URL {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/seeusage", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("history.json")
    }

    public static var resetsFileURL: URL {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/seeusage", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("resets.json")
    }

    private let historyURL: URL
    private let resetsURL: URL

    private var historyClearMarkerURL: URL {
        historyURL.deletingLastPathComponent().appendingPathComponent("history-cleared-at")
    }

    private var resetsClearMarkerURL: URL {
        resetsURL.deletingLastPathComponent().appendingPathComponent("resets-cleared-at")
    }

    private convenience init() {
        self.init(historyURL: Self.historyFileURL, resetsURL: Self.resetsFileURL)
    }

    public convenience init(storageDirectory: URL) {
        self.init(
            historyURL: storageDirectory.appendingPathComponent("history.json"),
            resetsURL: storageDirectory.appendingPathComponent("resets.json")
        )
    }

    private init(historyURL: URL, resetsURL: URL) {
        self.historyURL = historyURL
        self.resetsURL = resetsURL
        loadHistory()
        if Bundle.main.bundleIdentifier == nil || Bundle.main.bundleIdentifier == "app.seeusage.SeeUsage" {
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("app.seeusage.historyChanged"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.loadHistory() }
            }
        }
    }

    // MARK: - Persistence
    public func loadHistory() {
        let decoder = Self.historyDecoder()

        let historyData = SharedFileLock.withExclusiveLock(for: historyURL) {
            try? Data(contentsOf: historyURL)
        }
        if let data = historyData,
           let list = try? decoder.decode([QuotaHistorySnapshot].self, from: data) {
            self.snapshots = list.sorted { $0.timestamp < $1.timestamp }
            self.lastRecordedAt = self.snapshots.last?.timestamp
        }

        let resetData = SharedFileLock.withExclusiveLock(for: resetsURL) {
            try? Data(contentsOf: resetsURL)
        }
        if let data = resetData,
           let events = try? decoder.decode([ResetEvent].self, from: data) {
            self.resetEvents = events.sorted { $0.timestamp > $1.timestamp }
        }
    }

    public func saveHistory() {
        let encoder = JSONEncoder()
        // Numeric epoch dates preserve sample/batch identity across save/load. ISO 8601
        // without fractions rounded source timestamps and duplicated batches on merge.
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let decoder = Self.historyDecoder()

        SharedFileLock.withExclusiveLock(for: historyURL) {
            var byTimestamp: [Double: QuotaHistorySnapshot] = [:]
            if let data = try? Data(contentsOf: historyURL),
               let existing = try? decoder.decode([QuotaHistorySnapshot].self, from: data) {
                existing.forEach { byTimestamp[$0.id] = $0 }
            }
            snapshots.forEach { byTimestamp[$0.id] = $0 }
            if let clearDate = Self.readClearMarker(historyClearMarkerURL) {
                byTimestamp = byTimestamp.filter { $0.value.timestamp > clearDate }
            }
            // Weekly forecasts need several days even at one-minute polling with
            // independently refreshing providers. Keep older, sparsely sampled history too.
            snapshots = byTimestamp.values.sorted { $0.timestamp < $1.timestamp }.suffix(20_000)
                .map { $0 }
            if let data = try? encoder.encode(snapshots) {
                try? data.write(to: historyURL, options: .atomic)
            }
        }

        SharedFileLock.withExclusiveLock(for: resetsURL) {
            var byID: [UUID: ResetEvent] = [:]
            if let data = try? Data(contentsOf: resetsURL),
               let existing = try? decoder.decode([ResetEvent].self, from: data) {
                existing.forEach { byID[$0.id] = $0 }
            }
            resetEvents.forEach { byID[$0.id] = $0 }
            if let clearDate = Self.readClearMarker(resetsClearMarkerURL) {
                byID = byID.filter { $0.value.timestamp > clearDate }
            }
            resetEvents = byID.values.sorted { $0.timestamp > $1.timestamp }.prefix(1000).map { $0 }
            if let data = try? encoder.encode(resetEvents) {
                try? data.write(to: resetsURL, options: .atomic)
            }
        }
        postHistoryChanged()
    }

    public func clearHistory() {
        snapshots.removeAll()
        resetEvents.removeAll()
        lastRecordedAt = nil
        SharedFileLock.withExclusiveLock(for: historyURL) {
            Self.writeClearMarker(historyClearMarkerURL)
            try? FileManager.default.removeItem(at: historyURL)
        }
        SharedFileLock.withExclusiveLock(for: resetsURL) {
            Self.writeClearMarker(resetsClearMarkerURL)
            try? FileManager.default.removeItem(at: resetsURL)
        }
        postHistoryChanged()
    }

    public func clearResets() {
        resetEvents.removeAll()
        SharedFileLock.withExclusiveLock(for: resetsURL) {
            Self.writeClearMarker(resetsClearMarkerURL)
            try? FileManager.default.removeItem(at: resetsURL)
        }
        postHistoryChanged()
    }

    // MARK: - Recording Snapshots & Detecting Resets
    public func recordSnapshots(_ usageSnapshots: [UUID: UsageSnapshot]) {
        let settings = SettingsStore.shared
        var records: [QuotaSampleRecord] = []
        let now = Date()

        for (profileID, snapshot) in usageSnapshots where snapshot.error == nil && !snapshot.isStale {
            let profileName: String
            let service: String

            if profileID == SettingsStore.antigravityProfileID {
                profileName = "Antigravity"
                service = "Antigravity"
            } else if let p = settings.codexProfiles.first(where: { $0.id == profileID }) {
                profileName = p.name
                service = "Codex"
            } else {
                profileName = "Codex"
                service = "Codex"
            }

            for window in snapshot.windows {
                guard let pct = window.remainingPercent else { continue }
                records.append(QuotaSampleRecord(
                    timestamp: snapshot.fetchedAt,
                    profileID: profileID,
                    profileName: profileName,
                    service: service,
                    scope: window.scope,
                    windowLabel: window.label,
                    windowID: window.id,
                    durationMinutes: window.durationMinutes,
                    remainingPercent: pct,
                    resetsAt: window.resetsAt
                ))
            }
        }

        recordSamples(records, recordedAt: now)
    }

    public func recordClaudeUsage(_ snapshot: ClaudeUsageSnapshot) {
        let now = Date()
        let staleAfter = Double(max(600, SettingsStore.shared.refreshIntervalMinutes * 120))
        guard now.timeIntervalSince(snapshot.updatedAt) >= 0,
              now.timeIntervalSince(snapshot.updatedAt) <= staleAfter else { return }
        let records = snapshot.windows.compactMap { window -> QuotaSampleRecord? in
            guard let percent = window.remainingPercent else { return nil }
            return QuotaSampleRecord(
                timestamp: snapshot.updatedAt, profileID: ClaudeUsageSnapshot.profileID,
                profileName: "Claude Code", service: "Claude Code", scope: window.scope,
                windowLabel: window.label, windowID: window.id, durationMinutes: window.durationMinutes,
                remainingPercent: percent, resetsAt: window.resetsAt
            )
        }
        recordSamples(records, recordedAt: now)
    }

    private func recordSamples(_ samples: [QuotaSampleRecord], recordedAt now: Date) {
        // Sources refresh independently. Compare against each window's most recent sample,
        // rather than the last batch (which may contain only Claude or only Codex).
        let wanted = Set(samples.map(\.id))
        var lastRecordsMap: [String: QuotaSampleRecord] = [:]
        for snapshot in snapshots.reversed() {
            for record in snapshot.records where wanted.contains(record.id) {
                if let existing = lastRecordsMap[record.id], existing.timestamp >= record.timestamp { continue }
                lastRecordsMap[record.id] = record
            }
            if lastRecordsMap.count == wanted.count { break }
        }
        let records = samples.filter { record in
            guard record.remainingPercent.isFinite, (0...100).contains(record.remainingPercent),
                  record.timestamp <= now else { return false }
            guard let previous = lastRecordsMap[record.id] else { return true }
            let elapsed = record.timestamp.timeIntervalSince(previous.timestamp)
            return elapsed > 0.000_001 && (
                elapsed >= 45 || abs(record.remainingPercent - previous.remainingPercent) > 0.001 ||
                record.resetsAt != previous.resetsAt || record.durationMinutes != previous.durationMinutes
            )
        }
        guard !records.isEmpty else { return }

        // Detect reset events against each window's previous source reading.
        for newRecord in records {
            let key = newRecord.id
            guard let oldRecord = lastRecordsMap[key] else { continue }

            guard newRecord.remainingPercent > oldRecord.remainingPercent else { continue }
            let resetCycleAdvanced: Bool
            if let oldReset = oldRecord.resetsAt {
                let deadlineAdvanced = newRecord.resetsAt.map { $0.timeIntervalSince(oldReset) > 60 } ?? false
                resetCycleAdvanced = oldReset <= newRecord.timestamp || deadlineAdvanced
            } else {
                resetCycleAdvanced = false
            }

            if resetCycleAdvanced {
                let duration = newRecord.durationMinutes

                // Avoid duplicate logging within 2 minutes for the same window
                let isDuplicate = resetEvents.contains { past in
                    past.profileID == newRecord.profileID &&
                    past.windowLabel == newRecord.windowLabel &&
                    past.scope == newRecord.scope &&
                    abs(past.timestamp.timeIntervalSince(now)) < 120.0
                }

                if !isDuplicate {
                    let event = ResetEvent(
                        id: UUID(),
                        timestamp: now,
                        profileID: newRecord.profileID,
                        profileName: newRecord.profileName,
                        service: newRecord.service,
                        scope: newRecord.scope,
                        windowLabel: newRecord.windowLabel,
                        durationMinutes: duration,
                        quotaBefore: oldRecord.remainingPercent,
                        quotaAfter: newRecord.remainingPercent,
                        quotaRestored: max(0.0, newRecord.remainingPercent - oldRecord.remainingPercent),
                        nextResetAt: newRecord.resetsAt
                    )
                    resetEvents.insert(event, at: 0)
                }
            }
        }

        let newSnapshot = QuotaHistorySnapshot(timestamp: now, records: records)
        snapshots.append(newSnapshot)
        lastRecordedAt = now
        saveHistory()
    }

    // MARK: - Upcoming & Historical Resets Queries

    /// Gathers all currently active windows that have a scheduled resetsAt date
    public func computeUpcomingResets(from usageSnapshots: [UUID: UsageSnapshot]? = nil) -> [UpcomingResetInfo] {
        let snapshotsToUse = usageSnapshots ?? UsageStore.shared.snapshots
        let settings = SettingsStore.shared
        let activeProfileIDs = Set(settings.codexProfiles.map(\.id) + [SettingsStore.antigravityProfileID])
        var results: [UpcomingResetInfo] = []

        for (profileID, snapshot) in snapshotsToUse where activeProfileIDs.contains(profileID) {
            guard snapshot.error == nil, !snapshot.isStale else { continue }
            let profileName: String
            let service: String

            if profileID == SettingsStore.antigravityProfileID {
                profileName = "Antigravity"
                service = "Antigravity"
            } else if let p = settings.codexProfiles.first(where: { $0.id == profileID }) {
                profileName = p.name
                service = "Codex"
            } else {
                profileName = "Codex"
                service = "Codex"
            }

            for window in snapshot.windows {
                guard let resetDate = window.resetsAt else { continue }
                results.append(UpcomingResetInfo(
                    profileID: profileID,
                    profileName: profileName,
                    service: service,
                    scope: window.scope,
                    windowLabel: window.label,
                    windowID: window.id,
                    durationMinutes: window.durationMinutes,
                    currentRemainingPercent: window.remainingPercent,
                    resetsAt: resetDate
                ))
            }
        }

        // If active snapshots were empty (e.g. fresh CLI launch), fallback to latest history records
        if results.isEmpty, let lastSnap = snapshots.last {
            for record in lastSnap.records where activeProfileIDs.contains(record.profileID) {
                guard let resetDate = record.resetsAt, resetDate > Date() else { continue }
                results.append(UpcomingResetInfo(
                    profileID: record.profileID,
                    profileName: record.profileName,
                    service: record.service,
                    scope: record.scope,
                    windowLabel: record.windowLabel,
                    windowID: record.windowID,
                    durationMinutes: record.durationMinutes,
                    currentRemainingPercent: record.remainingPercent,
                    resetsAt: resetDate
                ))
            }
        }

        return results.sorted { $0.resetsAt < $1.resetsAt }
    }

    /// Retrieve reset history filtered by optional criteria
    public func getResetEvents(
        limit: Int = 100,
        service: String? = nil,
        profileID: UUID? = nil
    ) -> [ResetEvent] {
        var list = resetEvents
        if let s = service {
            list = list.filter { $0.service.lowercased() == s.lowercased() }
        }
        if let pid = profileID {
            list = list.filter { $0.profileID == pid }
        }
        return Array(list.prefix(limit))
    }

    // MARK: - Computations
    func quotaHints(
        for window: UsageWindow, profileID: UUID, service: String,
        windows: [UsageWindow], fetchedAt: Date, hasError: Bool = false,
        now: Date = Date()
    ) -> QuotaHints? {
        let interval = SettingsStore.shared.refreshIntervalMinutes
        return QuotaForecastCalculations.hints(
            for: window, profileID: profileID, service: service, windows: windows,
            history: snapshots, fetchedAt: fetchedAt, hasError: hasError, now: now,
            staleAfter: Double(max(600, interval * 120)),
            maximumSampleGap: Double(max(1_800, interval * 120))
        )
    }

    public func computeHourlyConsumption(days: Int = 7) -> [HourlyConsumption] {
        AnalyticsCalculations.hourlyConsumption(in: snapshots, days: days)
    }

    public func computeDailyConsumption(days: Int = 7) -> [DailyConsumption] {
        AnalyticsCalculations.dailyConsumption(in: snapshots, days: days)
    }

    public func computeProfileSummaries(days: Int = 7) -> [ProfileUsageSummary] {
        AnalyticsCalculations.profileSummaries(in: snapshots, days: days)
    }

    public func computeMetrics(days: Int = 7) -> AnalyticsMetrics {
        AnalyticsCalculations.metrics(in: snapshots, days: days)
    }

    // MARK: - Export Helpers
    public func exportCSV() -> String {
        var csv = "Timestamp,Profile,Service,Scope,Window,RemainingPercent,ResetsAt\n"
        let dateFormatter = ISO8601DateFormatter()

        for snapshot in snapshots {
            let timeStr = dateFormatter.string(from: snapshot.timestamp)
            for r in snapshot.records {
                let resetStr = r.resetsAt.map { dateFormatter.string(from: $0) } ?? ""
                let scopeStr = r.scope ?? ""
                csv += [timeStr, r.profileName, r.service, scopeStr, r.windowLabel]
                    .map(Self.csvField).joined(separator: ",")
                csv += ",\(r.remainingPercent),\(Self.csvField(resetStr))\n"
            }
        }
        return csv
    }

    public func exportJSON() -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(snapshots),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "[]"
    }

    public func exportResetsCSV() -> String {
        var csv = "Timestamp,Profile,Service,Scope,Window,QuotaBefore,QuotaAfter,QuotaRestored,NextResetAt\n"
        let dateFormatter = ISO8601DateFormatter()

        for event in resetEvents {
            let timeStr = dateFormatter.string(from: event.timestamp)
            let nextStr = event.nextResetAt.map { dateFormatter.string(from: $0) } ?? ""
            let scopeStr = event.scope ?? ""
            csv += [timeStr, event.profileName, event.service, scopeStr, event.windowLabel]
                .map(Self.csvField).joined(separator: ",")
            csv += ",\(event.quotaBefore),\(event.quotaAfter),\(event.quotaRestored),\(Self.csvField(nextStr))\n"
        }
        return csv
    }

    public func exportResetsJSON() -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(resetEvents),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "[]"
    }

    /// Extract all available banked reset credits across profiles
    public func getAvailableBankedCredits(
        from snapshots: [UUID: UsageSnapshot],
        profiles: [UsageProfile]
    ) -> [(profile: UsageProfile, credit: BankedResetCredit)] {
        var results: [(profile: UsageProfile, credit: BankedResetCredit)] = []
        for profile in profiles {
            guard let snap = snapshots[profile.id], snap.error == nil, !snap.isStale else { continue }
            for credit in snap.bankedCredits where credit.status.lowercased() == "available" {
                results.append((profile: profile, credit: credit))
            }
        }
        return results
    }

    /// Explicitly record a reset event (e.g. from banked reset consumption)
    public func recordResetEvent(_ event: ResetEvent) {
        let duplicate = resetEvents.contains {
            $0.profileID == event.profileID &&
            $0.windowLabel == event.windowLabel &&
            $0.scope == event.scope &&
            abs($0.timestamp.timeIntervalSince(event.timestamp)) < 120
        }
        guard !duplicate else { return }
        resetEvents.insert(event, at: 0)
        saveHistory()
    }

    private static func csvField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func historyDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let epoch = try? container.decode(Double.self), epoch.isFinite {
                return Date(timeIntervalSince1970: epoch)
            }
            // Existing history and reset files used ISO 8601 strings.
            let text = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid history date")
        }
        return decoder
    }

    private static func readClearMarker(_ url: URL) -> Date? {
        guard let value = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        if let epoch = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)), epoch.isFinite {
            return Date(timeIntervalSince1970: epoch)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func writeClearMarker(_ url: URL) {
        // Millisecond rounding can move a clear marker ahead of a newly recorded event.
        let value = String(Date().timeIntervalSince1970)
        try? Data(value.utf8).write(to: url, options: .atomic)
    }

    private func postHistoryChanged() {
        guard Bundle.main.bundleIdentifier == nil || Bundle.main.bundleIdentifier == "app.seeusage.SeeUsage" else { return }
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("app.seeusage.historyChanged"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}
