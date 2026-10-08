import Foundation
import XCTest
@testable import SeeUsage

final class QuotaPacingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testScreenshotSessionReserveIsBudgetDifferenceRatherThanProjectedSpare() throws {
        let window = quota(97, duration: 300, secondsLeft: 4 * 3_600 + 19 * 60)
        let pacing = try XCTUnwrap(QuotaPacing.calculate(for: window, fetchedAt: now, now: now))
        XCTAssertEqual(pacing.expectedRemainingPercent, 86.333333, accuracy: 0.00001)
        XCTAssertEqual(pacing.balancePercent, 10.666667, accuracy: 0.00001)
        XCTAssertEqual(pacing.status, .reserve)
        XCTAssertEqual(pacing.text, "11% in reserve · Lasts until reset")
        XCTAssertTrue(pacing.text.contains("Lasts until reset"))
        XCTAssertTrue(try XCTUnwrap(pacing.runsOutAt) > XCTUnwrap(window.resetsAt))
        XCTAssertNil(pacing.fullSessionWindowsLeft)
    }

    func testScreenshotWeeklyDeficitAndFullWindowsAreAvailableWithoutHistory() throws {
        let window = quota(87, duration: 10_080, secondsLeft: 6 * 86_400 + 12 * 3_600)
        let hints = try XCTUnwrap(QuotaForecastCalculations.hints(for: window, profileID: UUID(), service: "Codex",
                                                                 windows: [window], history: [], fetchedAt: now, now: now))
        XCTAssertEqual(hints.forecast.status, .learning)
        let pacing = try XCTUnwrap(hints.pacing)
        XCTAssertEqual(pacing.status, .deficit)
        XCTAssertEqual(pacing.balancePercent, -5.857143, accuracy: 0.00001)
        XCTAssertTrue(pacing.text.hasPrefix("6% in deficit · "))
        XCTAssertTrue(pacing.text.contains("Runs out in 3d"))
        XCTAssertEqual(pacing.fullSessionWindowsLeft, 31)
        XCTAssertEqual(pacing.windowText, "31 windows until reset")
        XCTAssertTrue(hints.tooltip.contains("31 windows until reset"))
        XCTAssertNil(hints.sessions)
    }

    func testClockCountsDownWithoutFabricatingNewUsageOrMovingReadingBudget() throws {
        let window = quota(87, duration: 10_080, secondsLeft: 6 * 86_400 + 12 * 3_600)
        let first = try XCTUnwrap(QuotaPacing.calculate(for: window, fetchedAt: now, now: now))
        let later = try XCTUnwrap(QuotaPacing.calculate(for: window, fetchedAt: now, now: now.addingTimeInterval(300)))
        XCTAssertEqual(first.balancePercent, later.balancePercent)
        XCTAssertEqual(first.expectedRemainingPercent, later.expectedRemainingPercent)
        XCTAssertEqual(first.runsOutAt, later.runsOutAt)
    }

    func testFullQuotaZeroQuotaAndNeutralPaceDoNotInventConsumption() throws {
        let full = try XCTUnwrap(QuotaPacing.calculate(for: quota(100, duration: 300, secondsLeft: 7_200), fetchedAt: now, now: now))
        XCTAssertEqual(full.status, .reserve)
        XCTAssertNil(full.runsOutAt)
        let exhausted = try XCTUnwrap(QuotaPacing.calculate(for: quota(0, duration: 300, secondsLeft: 7_200), fetchedAt: now, now: now))
        XCTAssertEqual(exhausted.status, .exhausted)
        let neutral = try XCTUnwrap(QuotaPacing.calculate(for: quota(40, duration: 300, secondsLeft: 7_200), fetchedAt: now, now: now))
        XCTAssertEqual(neutral.status, .onTrack)
        XCTAssertEqual(neutral.balancePercent, 0, accuracy: 0.00001)
    }

    func testJustStartedWindowsDoNotEstimateRunOutFromSecondsOfRoundedUsage() throws {
        let pacing = try XCTUnwrap(QuotaPacing.calculate(for: quota(97, duration: 300, secondsLeft: 17_990), fetchedAt: now, now: now))
        XCTAssertNil(pacing.runsOutAt)
        XCTAssertTrue(pacing.text.contains("Above planned pace"))
    }

    func testInvalidAndExpiredWindowsAreRejected() {
        for percent in [Double.nan, .infinity, -1, 101] {
            XCTAssertNil(QuotaPacing.calculate(for: quota(percent, duration: 300, secondsLeft: 7_200), fetchedAt: now, now: now))
        }
        XCTAssertNil(QuotaPacing.calculate(for: quota(80, duration: 300, secondsLeft: 0), fetchedAt: now, now: now))
        XCTAssertNil(QuotaPacing.calculate(for: quota(80, duration: 300, secondsLeft: 18_100), fetchedAt: now, now: now))
        XCTAssertNil(QuotaPacing.calculate(for: quota(80, duration: 0, secondsLeft: 7_200), fetchedAt: now, now: now))
        XCTAssertNil(QuotaPacing.calculate(for: quota(80, duration: 300, secondsLeft: 7_200), fetchedAt: now.addingTimeInterval(1), now: now))
    }

    func testReserveBucketDoesNotPretendToBeAnotherMainWeeklyPlan() {
        let reserve = UsageWindow(id: "reserve", label: "7 days", remainingPercent: 100, durationMinutes: 10_080,
                                  resetsAt: now.addingTimeInterval(604_800), scope: "base_model_inference")
        XCTAssertNil(QuotaForecastCalculations.hints(for: reserve, profileID: UUID(), service: "Codex", windows: [reserve],
                                                   history: [], fetchedAt: now, now: now))
    }

    private func quota(_ remaining: Double, duration: Int, secondsLeft: Double) -> UsageWindow {
        UsageWindow(id: "window", label: duration == 300 ? "5 h" : "7 days", remainingPercent: remaining,
                    durationMinutes: duration, resetsAt: now.addingTimeInterval(secondsLeft))
    }
}
