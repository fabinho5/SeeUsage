import XCTest
import Foundation
@testable import SeeUsage

@MainActor
final class AnalyticsTests: XCTestCase {
    private func makeAnalyticsManager() -> AnalyticsManager {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SeeUsageAnalyticsTests-\(UUID().uuidString)", isDirectory: true)
        return AnalyticsManager(storageDirectory: directory)
    }

    func testAnalyticsDataStructures() {
        let now = Date()
        let pID = UUID()

        let record = QuotaSampleRecord(
            timestamp: now,
            profileID: pID,
            profileName: "Personal",
            service: "Codex",
            scope: nil,
            windowLabel: "5 h",
            remainingPercent: 75.0,
            resetsAt: now.addingTimeInterval(3600)
        )

        XCTAssertEqual(record.usedPercent, 25.0)
        XCTAssertEqual(record.profileName, "Personal")
        XCTAssertEqual(record.service, "Codex")
        XCTAssertEqual(record.windowLabel, "5 h")

        let snapshot = QuotaHistorySnapshot(timestamp: now, records: [record])
        XCTAssertEqual(snapshot.records.count, 1)
        XCTAssertEqual(snapshot.records.first?.remainingPercent, 75.0)
    }

    func testHistoryDurationIsBackwardCompatible() throws {
        let record = QuotaSampleRecord(timestamp: Date(), profileID: UUID(), profileName: "Personal",
                                       service: "Codex", scope: nil, windowLabel: "5 h", windowID: "5h",
                                       durationMinutes: 300, remainingPercent: 80, resetsAt: nil)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(record)
        XCTAssertEqual(try decoder.decode(QuotaSampleRecord.self, from: data).durationMinutes, 300)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "durationMinutes")
        let restored = try decoder.decode(QuotaSampleRecord.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(restored.durationMinutes)
        XCTAssertEqual(restored.remainingPercent, 80)
    }

    func testHistorySaveReloadPreservesBatchIdentityAndReadsLegacyDates() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SeeUsageHistoryRoundTrip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) - 60)
        let profile = UUID()
        let reset = date.addingTimeInterval(3_600)
        let record = QuotaSampleRecord(timestamp: date, profileID: profile, profileName: "Personal",
                                       service: "Codex", scope: nil, windowLabel: "5 h", windowID: "5h",
                                       remainingPercent: 90, resetsAt: reset)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([QuotaHistorySnapshot(timestamp: date, records: [record])])
            .write(to: directory.appendingPathComponent("history.json"))
        let manager = AnalyticsManager(storageDirectory: directory)
        XCTAssertEqual(manager.snapshots.count, 1)
        let fetchedAt = Date()
        let usage = UsageSnapshot(profileID: profile,
                                  windows: [UsageWindow(id: "5h", label: "5 h", remainingPercent: 80,
                                                       durationMinutes: 300, resetsAt: reset)], fetchedAt: fetchedAt)
        manager.recordSnapshots([profile: usage])
        for _ in 0..<3 {
            manager.saveHistory()
            manager.loadHistory()
            manager.recordSnapshots([profile: usage])
        }
        XCTAssertEqual(manager.snapshots.count, 2)
        let restored = try XCTUnwrap(manager.snapshots.last?.records.first)
        XCTAssertEqual(restored.timestamp.timeIntervalSince1970, fetchedAt.timeIntervalSince1970, accuracy: 0.000_001)
        XCTAssertEqual(restored.durationMinutes, 300)
        let secondManager = AnalyticsManager(storageDirectory: directory)
        XCTAssertEqual(secondManager.snapshots.count, 2)
        XCTAssertEqual(secondManager.snapshots.map(\.id), manager.snapshots.map(\.id))
    }

    func testSourceTimestampsAndDeduplicationSurviveIndependentProviderBatches() throws {
        let manager = makeAnalyticsManager()
        let now = Date()
        let profile = UUID()
        let window = UsageWindow(id: "5h", label: "5 h", remainingPercent: 80,
                                 durationMinutes: 300, resetsAt: now.addingTimeInterval(3_600))
        let codex = UsageSnapshot(profileID: profile, windows: [window], fetchedAt: now.addingTimeInterval(-120))
        let claude = ClaudeUsageSnapshot(updatedAt: now.addingTimeInterval(-60), windows: [window])
        manager.recordSnapshots([profile: codex])
        manager.recordClaudeUsage(claude)
        manager.recordSnapshots([profile: codex])
        manager.recordClaudeUsage(claude)
        XCTAssertEqual(manager.snapshots.count, 2)
        let records = manager.snapshots.flatMap(\.records)
        XCTAssertEqual(records[0].timestamp.timeIntervalSince1970, codex.fetchedAt.timeIntervalSince1970, accuracy: 0.000_001)
        XCTAssertEqual(records[0].durationMinutes, 300)
        XCTAssertEqual(records[1].timestamp.timeIntervalSince1970, claude.updatedAt.timeIntervalSince1970, accuracy: 0.000_001)
        XCTAssertEqual(records[1].profileID, ClaudeUsageSnapshot.profileID)
        XCTAssertEqual(records[1].service, "Claude Code")
        // Another provider's recent batch must not suppress a fresh, unchanged reading.
        manager.recordSnapshots([profile: UsageSnapshot(profileID: profile, windows: [window], fetchedAt: now)])
        XCTAssertEqual(manager.snapshots.count, 3)
        // A reset deadline can advance while the quota percentage stays unchanged.
        let advanced = UsageWindow(id: "5h", label: "5 h", remainingPercent: 80,
                                   durationMinutes: 300, resetsAt: now.addingTimeInterval(18_000))
        manager.recordSnapshots([profile: UsageSnapshot(profileID: profile, windows: [advanced], fetchedAt: Date())])
        XCTAssertEqual(manager.snapshots.count, 4)
        XCTAssertEqual(manager.snapshots.last?.records.first?.resetsAt, advanced.resetsAt)
    }

    func testClaudeResetsAndStaleSamples() {
        let manager = makeAnalyticsManager()
        let now = Date()
        let old = UsageWindow(id: "claude-5h", label: "5 hours", remainingPercent: 10,
                              durationMinutes: 300, resetsAt: now.addingTimeInterval(-30))
        manager.recordClaudeUsage(ClaudeUsageSnapshot(updatedAt: now.addingTimeInterval(-60), windows: [old]))
        let current = UsageWindow(id: "claude-5h", label: "5 hours", remainingPercent: 100,
                                  durationMinutes: 300, resetsAt: now.addingTimeInterval(18_000))
        manager.recordClaudeUsage(ClaudeUsageSnapshot(updatedAt: now, windows: [current]))
        XCTAssertEqual(manager.resetEvents.count, 1)
        XCTAssertEqual(manager.resetEvents.first?.service, "Claude Code")
        XCTAssertEqual(manager.resetEvents.first?.durationMinutes, 300)
        manager.recordClaudeUsage(ClaudeUsageSnapshot(updatedAt: now.addingTimeInterval(-86_400), windows: [current]))
        XCTAssertEqual(manager.snapshots.count, 2)
    }

    func testAnalyticsManagerComputations() {
        let manager = makeAnalyticsManager()
        manager.clearHistory()
        XCTAssertEqual(manager.snapshots.count, 0)

        let profileID = UUID()
        let resetAt = Date().addingTimeInterval(3600)
        manager.recordSnapshots([profileID: UsageSnapshot(profileID: profileID, windows: [
            UsageWindow(id: "test-window", label: "5 h", remainingPercent: 90, durationMinutes: 300, resetsAt: resetAt)
        ])])
        manager.recordSnapshots([profileID: UsageSnapshot(profileID: profileID, windows: [
            UsageWindow(id: "test-window", label: "5 h", remainingPercent: 80, durationMinutes: 300, resetsAt: resetAt)
        ])])
        XCTAssertEqual(manager.snapshots.count, 2)

        // Compute metrics
        let metrics = manager.computeMetrics(days: 7)
        XCTAssertTrue(metrics.totalConsumption7Days >= 0.0)
        XCTAssertTrue(metrics.totalSamplesCount > 0)

        // Hourly consumption
        let hourly = manager.computeHourlyConsumption(days: 7)
        XCTAssertEqual(hourly.count, 24)

        // Daily consumption
        let daily = manager.computeDailyConsumption(days: 7)
        XCTAssertTrue(daily.count >= 0)

        // Profile summaries
        let profiles = manager.computeProfileSummaries(days: 7)
        XCTAssertTrue(profiles.count >= 0)

        // CSV & JSON export
        let csv = manager.exportCSV()
        XCTAssertTrue(csv.contains("Timestamp,Profile,Service,Scope,Window,RemainingPercent,ResetsAt"))

        let json = manager.exportJSON()
        XCTAssertTrue(json.contains("remainingPercent"))
    }

    func testCLIAnalyticsCommands() async {
        let handledGeneral = await CLIHandler.handle(arguments: ["seeusage", "analytics"])
        XCTAssertTrue(handledGeneral)

        let handledCSV = await CLIHandler.handle(arguments: ["seeusage", "analytics", "csv"])
        XCTAssertTrue(handledCSV)

        let handledJSON = await CLIHandler.handle(arguments: ["seeusage", "analytics", "json"])
        XCTAssertTrue(handledJSON)

        let handledHistoryAlias = await CLIHandler.handle(arguments: ["seeusage", "history"])
        XCTAssertTrue(handledHistoryAlias)
    }

    func testResetDataModels() {
        let now = Date()
        let pID = UUID()
        let nextReset = now.addingTimeInterval(18000)

        let event = ResetEvent(
            timestamp: now,
            profileID: pID,
            profileName: "Pessoal",
            service: "Codex",
            scope: nil,
            windowLabel: "5 h",
            durationMinutes: 300,
            quotaBefore: 12.0,
            quotaAfter: 100.0,
            quotaRestored: 88.0,
            nextResetAt: nextReset
        )

        XCTAssertEqual(event.profileName, "Pessoal")
        XCTAssertEqual(event.service, "Codex")
        XCTAssertEqual(event.windowLabel, "5 h")
        XCTAssertEqual(event.quotaBefore, 12.0)
        XCTAssertEqual(event.quotaAfter, 100.0)
        XCTAssertEqual(event.quotaRestored, 88.0)
        XCTAssertEqual(event.nextResetAt, nextReset)

        let upcoming = UpcomingResetInfo(
            profileID: pID,
            profileName: "Trabalho",
            service: "Codex",
            scope: nil,
            windowLabel: "7 days",
            durationMinutes: 10080,
            currentRemainingPercent: 65.0,
            resetsAt: now.addingTimeInterval(3600)
        )

        XCTAssertEqual(upcoming.profileName, "Trabalho")
        XCTAssertEqual(upcoming.windowLabel, "7 days")
        XCTAssertEqual(upcoming.currentRemainingPercent, 65.0)
        XCTAssertFalse(upcoming.isExpired)
        XCTAssertTrue(upcoming.secondsUntilReset > 0)
    }

    func testResetDetectionAndPersistence() {
        let manager = makeAnalyticsManager()
        manager.clearResets()
        XCTAssertEqual(manager.resetEvents.count, 0)

        manager.recordResetEvent(ResetEvent(
            profileID: UUID(),
            profileName: "Test",
            service: "Codex",
            windowLabel: "5 h",
            durationMinutes: 300,
            quotaBefore: 15,
            quotaAfter: 100
        ))
        XCTAssertGreaterThan(manager.resetEvents.count, 0)

        let events = manager.getResetEvents(limit: 10)
        XCTAssertFalse(events.isEmpty)

        // CSV export
        let csv = manager.exportResetsCSV()
        XCTAssertTrue(csv.contains("Timestamp,Profile,Service,Scope,Window,QuotaBefore,QuotaAfter,QuotaRestored,NextResetAt"))
        XCTAssertTrue(csv.contains("Codex"))

        // JSON export
        let json = manager.exportResetsJSON()
        XCTAssertTrue(json.contains("quotaRestored"))

        // Clear resets
        manager.clearResets()
        XCTAssertEqual(manager.resetEvents.count, 0)
    }

    func testClearMarkerPreservesEventsRecordedWithinTheNextMillisecond() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SeeUsageClearMarker-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = AnalyticsManager(storageDirectory: directory)
        manager.clearResets()
        let marker = try String(contentsOf: directory.appendingPathComponent("resets-cleared-at"), encoding: .utf8)
        let clearedAt = try XCTUnwrap(Double(marker))
        let event = ResetEvent(timestamp: Date(timeIntervalSince1970: clearedAt + 0.0001), profileID: UUID(),
                               profileName: "Test", service: "Codex", windowLabel: "5 h", quotaBefore: 10, quotaAfter: 100)
        manager.recordResetEvent(event)
        XCTAssertEqual(manager.resetEvents.map(\.id), [event.id])
        XCTAssertEqual(AnalyticsManager(storageDirectory: directory).resetEvents.map(\.id), [event.id])
    }

    func testUpcomingResetsComputation() {
        let manager = makeAnalyticsManager()
        let pID = UUID()
        let now = Date()
        let settings = SettingsStore.shared
        let originalProfiles = settings.codexProfiles
        defer { settings.codexProfiles = originalProfiles }
        settings.codexProfiles.append(UsageProfile(id: pID, provider: .codex, name: "Test"))

        let win5h = UsageWindow(
            id: "5h",
            label: "5 h",
            remainingPercent: 80.0,
            durationMinutes: 300,
            resetsAt: now.addingTimeInterval(7200),
            scope: nil
        )

        let win7d = UsageWindow(
            id: "7d",
            label: "7 days",
            remainingPercent: 60.0,
            durationMinutes: 10080,
            resetsAt: now.addingTimeInterval(86400),
            scope: nil
        )

        let snap = UsageSnapshot(
            profileID: pID,
            plan: "Pro",
            windows: [win7d, win5h]
        )

        let upcoming = manager.computeUpcomingResets(from: [pID: snap])
        XCTAssertEqual(upcoming.count, 2)
        // Earliest resetsAt should come first
        XCTAssertEqual(upcoming.first?.windowLabel, "5 h")
        XCTAssertEqual(upcoming.last?.windowLabel, "7 days")
    }

    func testCLIResetsCommands() async {
        let handledRemovedSeed = await CLIHandler.handle(arguments: ["seeusage", "resets", "seed"])
        XCTAssertTrue(handledRemovedSeed)

        let handledCSV = await CLIHandler.handle(arguments: ["seeusage", "resets", "csv"])
        XCTAssertTrue(handledCSV)
    }
}
