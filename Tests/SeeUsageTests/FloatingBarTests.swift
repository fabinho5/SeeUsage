import AppKit
import SwiftUI
import XCTest
@testable import SeeUsage

@MainActor
final class FloatingBarTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testBothQuotasPreserveProfileOrderAndIncludeClaude() {
        let personal = UsageProfile(provider: .codex, name: "Personal", homePath: "/tmp/personal")
        let work = UsageProfile(provider: .codex, name: "Work", homePath: "/tmp/work")
        let agy = UsageProfile(provider: .antigravity, name: "Antigravity")
        let items = FloatingQuotaItem.items(
            profiles: [work, personal, agy],
            snapshots: [
                personal.id: snapshot(personal, percentages: [90, 35]),
                work.id: snapshot(work, percentages: [84, 97]),
                agy.id: snapshot(agy, percentages: [100, 80])
            ],
            claudeUsage: ClaudeUsageSnapshot(updatedAt: now, windows: windows([70, 45])),
            refreshIntervalMinutes: 5,
            now: now
        )
        XCTAssertEqual(items.map(\.label), ["Work", "Personal", "Antigravity", "Claude"])
        XCTAssertEqual(items.map { $0.values.map(\.percent) }, [[84, 97], [90, 35], [100, 80], [70, 45]])
        XCTAssertEqual(items[0].id, work.id.uuidString)
    }

    func testMissingStaleAndFailedDataAreUnavailableInsteadOfHealthy() {
        let missing = UsageProfile(provider: .codex, name: "Missing")
        let stale = UsageProfile(provider: .codex, name: "Stale")
        let failed = UsageProfile(provider: .codex, name: "Failed")
        let agy = UsageProfile(provider: .antigravity, name: "Antigravity")
        let items = FloatingQuotaItem.items(
            profiles: [missing, stale, failed, agy],
            snapshots: [
                stale.id: snapshot(stale, percentages: [100], fetchedAt: now.addingTimeInterval(-601)),
                failed.id: snapshot(failed, percentages: [100], error: "Unavailable")
            ],
            claudeUsage: ClaudeUsageSnapshot(updatedAt: now.addingTimeInterval(-601), windows: windows([100])),
            refreshIntervalMinutes: 5,
            now: now
        )
        XCTAssertEqual(items.map(\.label), ["Missing", "Stale", "Failed", "Antigravity", "Claude"])
        XCTAssertTrue(items.allSatisfy { $0.values.allSatisfy { $0.percent == nil } })
    }

    func testVisibilityFiltersIndividualProfilesAndProvidersWithoutChangingQuotas() {
        let personal = UsageProfile(provider: .codex, name: "Personal")
        let work = UsageProfile(provider: .codex, name: "Work")
        let agy = UsageProfile(provider: .antigravity, name: "Antigravity")
        let items = FloatingQuotaItem.items(
            profiles: [personal, agy, work],
            snapshots: [work.id: snapshot(work, percentages: [84, 97]),
                        agy.id: snapshot(agy, percentages: [100, 80])],
            claudeUsage: ClaudeUsageSnapshot(updatedAt: now, windows: windows([70, 45])),
            refreshIntervalMinutes: 5,
            hiddenItems: [personal.id.uuidString, FloatingBarVisibility.antigravity], now: now
        )
        XCTAssertEqual(items.map(\.label), ["Work", "Claude"])
        XCTAssertEqual(items.map { $0.values.map(\.percent) }, [[84, 97], [70, 45]])
    }

    func testProviderChoicePreservesIndividualProfileChoices() {
        let personal = UsageProfile(provider: .codex, name: "Personal")
        let work = UsageProfile(provider: .codex, name: "Work")
        var hidden: Set<String> = [FloatingBarVisibility.codex, personal.id.uuidString]
        XCTAssertFalse(FloatingBarVisibility.includes(work, hiddenItems: hidden))
        hidden.remove(FloatingBarVisibility.codex)
        XCTAssertTrue(FloatingBarVisibility.includes(work, hiddenItems: hidden))
        XCTAssertFalse(FloatingBarVisibility.includes(personal, hiddenItems: hidden))
        let newProfile = UsageProfile(provider: .codex, name: "New")
        XCTAssertTrue(FloatingBarVisibility.includes(newProfile, hiddenItems: hidden))
    }

    func testAllProvidersCanBeHiddenIncludingClaude() {
        let personal = UsageProfile(provider: .codex, name: "Personal")
        let agy = UsageProfile(provider: .antigravity, name: "Antigravity")
        let items = FloatingQuotaItem.items(
            profiles: [personal, agy], snapshots: [agy.id: snapshot(agy, percentages: [100, 80])],
            claudeUsage: ClaudeUsageSnapshot(updatedAt: now, windows: windows([70, 45])),
            refreshIntervalMinutes: 5,
            hiddenItems: [FloatingBarVisibility.codex, FloatingBarVisibility.antigravity, FloatingBarVisibility.claude],
            now: now
        )
        XCTAssertTrue(items.isEmpty)
    }

    func testInvalidPercentagesAreFilteredAndValuesAreClamped() {
        let profile = UsageProfile(provider: .codex, name: "Personal")
        let items = FloatingQuotaItem.items(
            profiles: [profile],
            snapshots: [profile.id: snapshot(profile, percentages: [.nan, .infinity, -4, 110])],
            claudeUsage: nil,
            refreshIntervalMinutes: 5,
            now: now
        )
        XCTAssertEqual(items.first?.values.map(\.percent), [0, 100])
    }

    func testBarSizeIsStableAcrossRefreshesAndFitsTheScreen() {
        let items = [FloatingQuotaItem(id: "personal", label: "Personal", values: [FloatingQuotaValue(period: .fiveHours, percent: 100)])]
        let refreshed = [FloatingQuotaItem(id: "personal", label: "Personal", values: [FloatingQuotaValue(period: .fiveHours, percent: 3)])]
        XCTAssertEqual(
            FloatingBarLayout.size(items: items, availableWidth: 1280),
            FloatingBarLayout.size(items: refreshed, availableWidth: 1280)
        )
        let manyItems = (0..<20).map { FloatingQuotaItem(id: "\($0)", label: "Profile \($0)", values: [FloatingQuotaValue(period: .fiveHours, percent: 100)]) }
        let size = FloatingBarLayout.size(items: manyItems, availableWidth: 800)
        XCTAssertTrue(size.width <= 768)
        XCTAssertEqual(size.height, FloatingBarLayout.horizontalRowHeight + 2 * FloatingBarLayout.verticalPadding)
    }

    func testSingleQuotaSelectionsDoNotMixPeriods() {
        let profile = UsageProfile(provider: .codex, name: "Personal")
        for selection in [FloatingBarQuotas.fiveHours, .weekly] {
            let items = FloatingQuotaItem.items(
                profiles: [profile], snapshots: [profile.id: snapshot(profile, percentages: [90, 35])],
                claudeUsage: nil, refreshIntervalMinutes: 5, quotas: selection, now: now
            )
            XCTAssertEqual(items.first?.values.count, 1)
            XCTAssertEqual(items.first?.values.first?.period, selection == .fiveHours ? .fiveHours : .weekly)
            XCTAssertEqual(items.first?.values.first?.percent, selection == .fiveHours ? 90 : 35)
        }
    }

    func testMissingWeeklyQuotaIsUnavailableInsteadOfUsingSessionQuota() {
        let profile = UsageProfile(provider: .codex, name: "Personal")
        let items = FloatingQuotaItem.items(
            profiles: [profile], snapshots: [profile.id: snapshot(profile, percentages: [90])],
            claudeUsage: nil, refreshIntervalMinutes: 5, quotas: .weekly, now: now
        )
        XCTAssertEqual(items.first?.values.first?.period, .weekly)
        XCTAssertNil(items.first?.values.first?.percent)
    }

    func testDurationTakesPrecedenceAndKnownLabelsWorkWithoutDuration() {
        XCTAssertTrue(FloatingQuotaPeriod.fiveHours.matches(UsageWindow(id: "session", label: "5 hours", remainingPercent: 90)))
        XCTAssertTrue(FloatingQuotaPeriod.weekly.matches(UsageWindow(id: "week", label: "Weekly", remainingPercent: 35)))
        XCTAssertFalse(FloatingQuotaPeriod.weekly.matches(UsageWindow(id: "other", label: "Weekly", remainingPercent: 35, durationMinutes: 120)))
    }

    func testVerticalLayoutFitsTheScreenAndBothQuotasUseMoreWidth() {
        let items = (0..<50).map {
            FloatingQuotaItem(id: "\($0)", label: "Profile \($0)", values: [FloatingQuotaValue(period: .fiveHours, percent: 100)])
        }
        for selection in FloatingBarQuotas.allCases {
            let size = FloatingBarLayout.size(items: items, availableWidth: 800, availableHeight: 600, orientation: .vertical, quotas: selection)
            XCTAssertTrue(size.width <= 768)
            XCTAssertTrue(size.height <= 568)
        }
        let both = FloatingBarLayout.size(items: items, availableWidth: 800, orientation: .vertical, quotas: .both)
        let single = FloatingBarLayout.size(items: items, availableWidth: 800, orientation: .vertical, quotas: .fiveHours)
        XCTAssertTrue(both.width > single.width)
    }

    func testThreeProfilesFitTheActualViewInEveryOrientationAndQuotaMode() {
        let profiles = ["Personal", "Work", "Third profile with a long name"].map {
            UsageProfile(provider: .codex, name: $0)
        }
        for quotas in FloatingBarQuotas.allCases {
            let items = FloatingQuotaItem.items(profiles: profiles, snapshots: [:], claudeUsage: nil,
                                                refreshIntervalMinutes: 5, quotas: quotas, now: now)
            XCTAssertEqual(items.count, 3)
            XCTAssertEqual(items.last?.id, profiles.last?.id.uuidString)
            for orientation in FloatingBarOrientation.allCases {
                let view = NSHostingView(rootView: FloatingQuotaBar(items: items, orientation: orientation, quotas: quotas))
                let panelSize = FloatingBarLayout.size(items: items, availableWidth: 1280,
                                                       orientation: orientation, quotas: quotas)
                XCTAssertTrue(abs(view.fittingSize.width - panelSize.width) <= 1)
                XCTAssertTrue(abs(view.fittingSize.height - panelSize.height) <= 1)
            }
        }
    }

    private func windows(_ percentages: [Double]) -> [UsageWindow] {
        percentages.enumerated().map {
            UsageWindow(id: "\($0.offset)", label: $0.offset % 2 == 0 ? "5 h" : "7 days", remainingPercent: $0.element, durationMinutes: $0.offset % 2 == 0 ? 300 : 10_080)
        }
    }

    private func snapshot(
        _ profile: UsageProfile,
        percentages: [Double],
        fetchedAt: Date? = nil,
        error: String? = nil
    ) -> UsageSnapshot {
        UsageSnapshot(profileID: profile.id, windows: windows(percentages), fetchedAt: fetchedAt ?? now, error: error)
    }
}
