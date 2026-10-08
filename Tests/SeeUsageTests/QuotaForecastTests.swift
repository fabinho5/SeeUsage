import Foundation
import XCTest
@testable import SeeUsage

final class QuotaForecastTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let profileID = UUID()

    func testReserveAndDeficitUseThisWindowsConsumption() throws {
        let reserve = try XCTUnwrap(hints(remaining: 70, percentages: [90, 80, 70]))
        XCTAssertEqual(reserve.forecast.status, .reserve)
        XCTAssertEqual(try XCTUnwrap(reserve.forecast.projectedRemainingPercent), 50, accuracy: 0.001)
        let deficit = try XCTUnwrap(hints(remaining: 10, percentages: [30, 20, 10]))
        XCTAssertEqual(deficit.forecast.status, .deficit)
        XCTAssertEqual(try XCTUnwrap(deficit.forecast.secondsBeforeReset), 1_800, accuracy: 0.001)
        XCTAssertTrue(deficit.forecast.text.contains("30m before reset"))
    }

    func testCloseForecastHasNeutralLabelWithoutPromisingEnoughQuota() throws {
        let positive = try XCTUnwrap(hints(remaining: 23, percentages: [43, 33, 23]))
        let negative = try XCTUnwrap(hints(remaining: 17, percentages: [37, 27, 17]))
        XCTAssertEqual(positive.forecast.status, .onTrack)
        XCTAssertEqual(negative.forecast.status, .onTrack)
        XCTAssertTrue(positive.forecast.text.contains("Lasts until reset"))
        XCTAssertTrue(negative.forecast.text.contains("may run out"))
    }

    func testIdleDoesNotInventUnlimitedCapacityAndZeroQuotaIsExhausted() {
        XCTAssertEqual(hints(remaining: 80, percentages: [80, 80, 80])?.forecast.status, .idle)
        XCTAssertEqual(hints(remaining: 0, percentages: [])?.forecast.status, .exhausted)
    }

    func testSparseDuplicateAndShortHistoryKeepLearning() {
        let window = shortWindow(70)
        let sample = record(window: window, at: now.addingTimeInterval(-3_600), remaining: 90)
        let duplicated = (0..<10).map { _ in snapshot([sample]) }
        XCTAssertEqual(calculate(window: window, history: duplicated)?.forecast.status, .learning)
        let tooShort = [record(window: window, at: now.addingTimeInterval(-600), remaining: 90),
                        record(window: window, at: now.addingTimeInterval(-300), remaining: 80)]
        XCTAssertEqual(calculate(window: window, history: tooShort.map { snapshot([$0]) })?.forecast.status, .learning)
    }

    func testStaleFailedMissingExpiredAndInvalidInputsSuppressHints() {
        let window = shortWindow(70)
        XCTAssertNil(calculate(window: window, history: [], fetchedAt: now.addingTimeInterval(-601)))
        XCTAssertNil(calculate(window: window, history: [], fetchedAt: now.addingTimeInterval(1)))
        XCTAssertNil(calculate(window: window, history: [], hasError: true))
        for value in [Double.nan, .infinity, -1, 101] {
            XCTAssertNil(calculate(window: shortWindow(value), history: []))
        }
        XCTAssertNil(calculate(window: UsageWindow(id: "5h", label: "5 h", remainingPercent: 70), history: []))
        XCTAssertNil(calculate(window: shortWindow(70, reset: now), history: []))
    }

    func testProfileProviderScopeAndWindowAreNeverMixed() {
        let window = shortWindow(70)
        for identity in 0..<4 {
            let records = [90.0, 80.0].enumerated().map { index, percent in
                record(window: identity == 3 ? weeklyWindow(70) : window,
                       at: now.addingTimeInterval(Double(index - 2) * 1_800), remaining: percent,
                       profile: identity == 0 ? UUID() : profileID,
                       service: identity == 1 ? "Antigravity" : "Codex", scope: identity == 2 ? "Other" : nil)
            }
            XCTAssertEqual(calculate(window: window, history: records.map { snapshot([$0]) })?.forecast.status, .learning)
        }
    }

    func testResetsRefillsInvalidSamplesAndLongGapsEndShortForecastHistory() {
        let window = shortWindow(70)
        let previousCycle = shortWindow(80, reset: now.addingTimeInterval(-60))
        let resetHistory = [record(window: previousCycle, at: now.addingTimeInterval(-3_600), remaining: 90),
                            record(window: previousCycle, at: now.addingTimeInterval(-1_800), remaining: 80)]
        XCTAssertEqual(calculate(window: window, history: resetHistory.map { snapshot([$0]) })?.forecast.status, .learning)
        XCTAssertEqual(hints(remaining: 70, percentages: [90, 60, 70])?.forecast.status, .learning)
        XCTAssertEqual(hints(remaining: 70, percentages: [90, .nan, 70])?.forecast.status, .learning)
        let gapHistory = [record(window: window, at: now.addingTimeInterval(-7_200), remaining: 90),
                          record(window: window, at: now.addingTimeInterval(-1_800), remaining: 80)]
        XCTAssertEqual(calculate(window: window, history: gapHistory.map { snapshot([$0]) })?.forecast.status, .learning)
    }

    func testUIClockDoesNotImproveForecastWithoutNewQuotaData() throws {
        let window = shortWindow(70)
        let history = shortHistory(window, percentages: [90, 80, 70])
        let original = try XCTUnwrap(calculate(window: window, history: history))
        let later = try XCTUnwrap(calculate(window: window, history: history, clock: now.addingTimeInterval(300)))
        XCTAssertEqual(original.forecast, later.forecast)
    }

    func testWeeklyUsesObservedWallTimeAndRequiresThreeDays() throws {
        let window = weeklyWindow(64)
        let history = (0...144).map { step in
            snapshot([record(window: window, at: now.addingTimeInterval(Double(step - 144) * 1_800),
                             remaining: 100 - Double(step) * 0.25)])
        }
        let result = try XCTUnwrap(calculate(window: window, history: history))
        XCTAssertEqual(result.forecast.status, .reserve)
        XCTAssertEqual(try XCTUnwrap(result.forecast.projectedRemainingPercent), 28, accuracy: 0.001)
        XCTAssertEqual(result.sessionText, "Learning your sessions")
        XCTAssertEqual(calculate(window: window, history: Array(history.suffix(100)))?.forecast.status, .learning)
    }

    func testWeeklyRejectsHistoryWithMostlyUnobservedTime() {
        let window = weeklyWindow(64)
        let history = [snapshot([record(window: window, at: now.addingTimeInterval(-3 * 86_400), remaining: 100)]),
                       snapshot([record(window: window, at: now.addingTimeInterval(-1_800), remaining: 65)])]
        XCTAssertEqual(calculate(window: window, history: history)?.forecast.status, .learning)
    }

    func testWeeklySessionsUseMedianOfCompletedSessions() throws {
        let window = weeklyWindow(35)
        let history = sessionHistory(costs: [5, 10, 50])
        let result = try XCTUnwrap(calculate(window: window, history: history))
        let estimate = try XCTUnwrap(result.sessions)
        XCTAssertEqual(estimate.observedSessions, 3)
        XCTAssertEqual(estimate.typicalConsumption, 10, accuracy: 0.001)
        XCTAssertEqual(estimate.count, 3)
        XCTAssertEqual(try XCTUnwrap(estimate.fractionalCount), 3.5, accuracy: 0.001)
        XCTAssertEqual(estimate.text, "~\(3.5.formatted(.number.precision(.fractionLength(0...1)))) typical 5-hour sessions left")
        XCTAssertNil(calculate(window: window, history: sessionHistory(costs: [5, 10]))?.sessions)
        XCTAssertEqual(calculate(window: weeklyWindow(4), history: history)?.sessions?.count, 0)
    }

    func testIncompleteAmbiguousRefilledAndGappedSessionsAreExcluded() {
        let window = weeklyWindow(35)
        let good = sessionHistory(costs: [5, 10, 50])
        let incomplete = good.filter { $0.records[0].timestamp.timeIntervalSince(now.addingTimeInterval(-20 * 3_600)) >= 900 }
        XCTAssertNil(calculate(window: window, history: incomplete)?.sessions)
        let gapped = good.enumerated().filter { $0.offset < 10 || $0.offset > 25 }.map(\.element)
        XCTAssertNil(calculate(window: window, history: gapped)?.sessions)
        let ambiguous = UsageWindow(id: "other", label: "5 h", remainingPercent: 80, durationMinutes: 300)
        XCTAssertNil(calculate(window: window, history: good, windows: [window, shortWindow(80), ambiguous])?.sessions)
        var refill = good
        let previous = good[20].records
        refill[20] = snapshot([previous[0], record(window: window, at: previous[1].timestamp, remaining: 100)])
        XCTAssertNil(calculate(window: window, history: refill)?.sessions)
        var reset = good
        let old = good[20].records
        reset[20] = snapshot([old[0], record(window: weeklyWindow(90, reset: now.addingTimeInterval(4 * 86_400)),
                                            at: old[1].timestamp, remaining: old[1].remainingPercent)])
        XCTAssertNil(calculate(window: window, history: reset)?.sessions)
    }

    func testLegacyHistoryWithoutWindowIDStillForecasts() throws {
        let window = shortWindow(70)
        let history = [90.0, 80.0, 70.0].enumerated().map { step, percent in
            snapshot([QuotaSampleRecord(timestamp: now.addingTimeInterval(Double(step - 2) * 1_800),
                                        profileID: profileID, profileName: "Personal", service: "Codex", scope: nil,
                                        windowLabel: window.label, remainingPercent: percent, resetsAt: window.resetsAt)])
        }
        XCTAssertEqual(try XCTUnwrap(calculate(window: window, history: history)).forecast.status, .reserve)
    }

    func testShortLookbackFollowsSourceTimeAndIgnoresSnapshotMetadata() throws {
        let window = shortWindow(70)
        let reading = now.addingTimeInterval(-300)
        let samples = [90.0, 85, 80, 75, 70].enumerated().map { step, percent in
            record(window: window, at: reading.addingTimeInterval(Double(step - 4) * 1_800), remaining: percent)
        }
        let original = try XCTUnwrap(calculate(window: window, history: samples.map { snapshot([$0]) }, fetchedAt: reading))
        let decorated = samples.map { sample in
            QuotaHistorySnapshot(timestamp: now.addingTimeInterval(-30 * 86_400), records: [
                record(window: window, at: reading.addingTimeInterval(-7_201), remaining: 1),
                record(window: window, at: sample.timestamp, remaining: 0, profile: UUID()), sample
            ])
        }
        XCTAssertEqual(calculate(window: window, history: decorated, fetchedAt: reading), original)
        XCTAssertEqual(original.forecast.observedSeconds, 7_200)
        XCTAssertEqual(original.forecast.sampleCount, 5)
    }

    func testCompletedSessionsAtTheFourteenDayBoundaryRemainUsable() throws {
        let shift = -14 * 86_400.0 + 20 * 3_600
        let history = sessionHistory(costs: [5, 10, 50]).map { entry in
            snapshot(entry.records.map { sample in
                let window = sample.windowID == "5h"
                    ? shortWindow(80, reset: sample.resetsAt?.addingTimeInterval(shift)) : weeklyWindow(35)
                return record(window: window, at: sample.timestamp.addingTimeInterval(shift),
                              remaining: sample.remainingPercent)
            })
        }
        let result = try XCTUnwrap(calculate(window: weeklyWindow(35), history: history,
                                            fetchedAt: now.addingTimeInterval(-300)))
        let estimate = try XCTUnwrap(result.sessions)
        XCTAssertEqual(estimate.observedSessions, 3)
        XCTAssertEqual(estimate.typicalConsumption, 10)
        XCTAssertEqual(estimate.fractionalCount, 3.5)
    }

    private func hints(remaining: Double, percentages: [Double]) -> QuotaHints? {
        let window = shortWindow(remaining)
        return calculate(window: window, history: shortHistory(window, percentages: percentages))
    }

    private func shortHistory(_ window: UsageWindow, percentages: [Double]) -> [QuotaHistorySnapshot] {
        percentages.enumerated().map { index, percent in
            snapshot([record(window: window, at: now.addingTimeInterval(Double(index - percentages.count + 1) * 1_800), remaining: percent)])
        }
    }

    private func calculate(
        window: UsageWindow, history: [QuotaHistorySnapshot], fetchedAt: Date? = nil,
        hasError: Bool = false, clock: Date? = nil, windows: [UsageWindow]? = nil
    ) -> QuotaHints? {
        QuotaForecastCalculations.hints(for: window, profileID: profileID, service: "Codex",
                                       windows: windows ?? [shortWindow(80), weeklyWindow(35)], history: history,
                                       fetchedAt: fetchedAt ?? now, hasError: hasError, now: clock ?? now)
    }

    private func shortWindow(_ remaining: Double, reset: Date? = nil) -> UsageWindow {
        UsageWindow(id: "5h", label: "5 h", remainingPercent: remaining, durationMinutes: 300,
                    resetsAt: reset ?? now.addingTimeInterval(3_600))
    }

    private func weeklyWindow(_ remaining: Double, reset: Date? = nil) -> UsageWindow {
        UsageWindow(id: "7d", label: "7 days", remainingPercent: remaining, durationMinutes: 10_080,
                    resetsAt: reset ?? now.addingTimeInterval(3 * 86_400))
    }

    private func record(
        window: UsageWindow, at: Date, remaining: Double, profile: UUID? = nil,
        service: String = "Codex", scope: String? = nil
    ) -> QuotaSampleRecord {
        QuotaSampleRecord(timestamp: at, profileID: profile ?? profileID, profileName: "Personal",
                          service: service, scope: scope, windowLabel: window.label, windowID: window.id,
                          durationMinutes: window.durationMinutes, remainingPercent: remaining, resetsAt: window.resetsAt)
    }

    private func snapshot(_ records: [QuotaSampleRecord]) -> QuotaHistorySnapshot {
        QuotaHistorySnapshot(timestamp: records.map(\.timestamp).max() ?? now, records: records)
    }

    private func sessionHistory(costs: [Double]) -> [QuotaHistorySnapshot] {
        var results: [QuotaHistorySnapshot] = []
        var weeklyRemaining = 100.0
        for (index, cost) in costs.enumerated() {
            let end = now.addingTimeInterval(Double(index - 3) * 18_000)
            for step in 0..<60 {
                let time = end.addingTimeInterval(-18_000 + Double(step) * 300)
                let fraction = Double(step) / 59
                results.append(snapshot([
                    record(window: shortWindow(80, reset: end), at: time, remaining: 100 - fraction * 80),
                    record(window: weeklyWindow(35), at: time, remaining: weeklyRemaining - fraction * cost)
                ]))
            }
            weeklyRemaining -= cost
        }
        return results
    }
}
