import AppKit
import XCTest
@testable import SeeUsage

@MainActor
final class MenuBarPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(_ profile: UsageProfile, session: Double = 39, weekly: Double = 88,
                          date: Date? = nil, error: String? = nil) -> UsageSnapshot {
        UsageSnapshot(profileID: profile.id, windows: [
            UsageWindow(id: "session", label: "5 h", remainingPercent: session, durationMinutes: 300,
                        resetsAt: now.addingTimeInterval(3_600)),
            UsageWindow(id: "weekly", label: "7 days", remainingPercent: weekly, durationMinutes: 10_080,
                        resetsAt: now.addingTimeInterval(86_400)),
            UsageWindow(id: "reserve", label: "7 days", remainingPercent: 2, durationMinutes: 10_080,
                        resetsAt: now.addingTimeInterval(86_400), scope: "base_model_inference")
        ], fetchedAt: date ?? now, error: error)
    }

    func testEachAccountKeepsItsOwnQuotaOrderAndVisualName() {
        let first = UsageProfile(provider: .codex, name: "Codex")
        let second = UsageProfile(provider: .codex, name: "Codex")
        let snapshots = [first.id: snapshot(first), second.id: snapshot(second, session: 97, weekly: 87)]
        for (quota, expected) in [(MenuBarQuota.fiveHours, [97, 39]), (.weekly, [87, 88]), (.lowest, [87, 39])] {
            let items = MenuBarQuotaItem.items(profiles: [second, first], snapshots: snapshots, claudeUsage: nil,
                                               preferences: MenuBarPreferences(quota: quota),
                                               displayNames: [second.id: "Work", first.id: "Personal"], now: now)
            XCTAssertEqual(items.map(\.id), [second.id.uuidString, first.id.uuidString])
            XCTAssertEqual(items.map(\.label), ["Work", "Personal"])
            XCTAssertEqual(items.compactMap(\.percent), expected)
            let tooltip = MenuBarQuotaItem.tooltip(items: items, quota: quota, mode: .stackedBars)
            XCTAssertTrue(tooltip.contains("Work: \(expected[0])%"))
            XCTAssertTrue(tooltip.contains("Personal: \(expected[1])%"))
        }
    }

    func testSelectionIsIndependentOfFloatingBarAndFiltersBeforeGrouping() {
        let personal = UsageProfile(provider: .codex, name: "Personal")
        let work = UsageProfile(provider: .codex, name: "Work")
        let ag = UsageProfile(provider: .antigravity, name: "Antigravity")
        let snapshots = [personal.id: snapshot(personal), work.id: snapshot(work, session: 97), ag.id: snapshot(ag)]
        var preferences = MenuBarPreferences(grouping: .providers,
                                             hiddenItems: [personal.id.uuidString, FloatingBarVisibility.antigravity])
        let items = MenuBarQuotaItem.items(profiles: [personal, ag, work], snapshots: snapshots, claudeUsage: nil,
                                           preferences: preferences, now: now)
        XCTAssertEqual(items.map(\.id), ["provider:codex"])
        XCTAssertEqual(items.first?.percent, 97)
        XCTAssertEqual(items.first?.label, "Codex (Work)")
        preferences.hiddenItems.insert(FloatingBarVisibility.codex)
        XCTAssertTrue(MenuBarQuotaItem.items(profiles: [personal, work, ag], snapshots: snapshots,
                                             claudeUsage: nil, preferences: preferences, now: now).isEmpty)
    }

    func testProviderGroupsKeepProviderOrderAndUseLowestSelectedAccount() {
        let first = UsageProfile(provider: .codex, name: "Personal")
        let second = UsageProfile(provider: .codex, name: "Work")
        let ag = UsageProfile(provider: .antigravity, name: "Antigravity")
        let items = MenuBarQuotaItem.items(profiles: [ag, second, first], snapshots: [
            first.id: snapshot(first), second.id: snapshot(second, session: 97), ag.id: snapshot(ag, session: 85)
        ], claudeUsage: ClaudeUsageSnapshot(updatedAt: now, windows: [
            UsageWindow(id: "claude", label: "5 h", remainingPercent: 64, durationMinutes: 300)
        ]), preferences: MenuBarPreferences(grouping: .providers), now: now)
        XCTAssertEqual(items.map(\.id), ["provider:antigravity", "provider:codex", "provider:claude"])
        XCTAssertEqual(items.compactMap(\.percent), [85, 39, 64])
        XCTAssertEqual(items[1].label, "Codex (Work, Personal)")
    }

    func testUnavailableExpiredAndInvalidReadingsNeverAppearAsFullBars() {
        let profiles = (0..<6).map { UsageProfile(provider: .codex, name: "Account \($0)") }
        let data = [
            profiles[1].id: snapshot(profiles[1], date: now.addingTimeInterval(-601)),
            profiles[2].id: snapshot(profiles[2], error: "Unavailable"),
            profiles[3].id: snapshot(profiles[3], session: .nan),
            profiles[4].id: snapshot(profiles[4], session: 101),
            profiles[5].id: UsageSnapshot(profileID: profiles[5].id, windows: [
                UsageWindow(id: "expired", label: "5 h", remainingPercent: 100, durationMinutes: 300,
                            resetsAt: now.addingTimeInterval(-1))
            ], fetchedAt: now)
        ]
        let items = MenuBarQuotaItem.items(profiles: profiles, snapshots: data, claudeUsage: nil,
                                           preferences: MenuBarPreferences(), now: now)
        XCTAssertEqual(items.count, profiles.count)
        XCTAssertTrue(items.allSatisfy { $0.percent == nil && $0.percentText == "–" })
        XCTAssertTrue(MenuBarQuotaItem.tooltip(items: items, quota: .fiveHours, mode: .stackedBars).contains("Unavailable"))
    }

    func testPreferencesPersistWithoutChangingOtherPresentationOrProviderSettings() throws {
        let domain = "SeeUsageMenuBarTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let settings = SettingsStore(presentationDefaults: defaults)
        let presentation = settings.profilePresentation
        let floatingHidden = settings.hudBarHiddenItems
        let profiles = settings.codexProfiles
        let preference = MenuBarPreferences(quota: .weekly, grouping: .providers,
                                            hiddenItems: [FloatingBarVisibility.antigravity, UUID().uuidString])
        settings.menuBarPreferences = preference
        let restored = SettingsStore(presentationDefaults: defaults)
        XCTAssertEqual(restored.menuBarPreferences, preference)
        XCTAssertEqual(restored.profilePresentation, presentation)
        XCTAssertEqual(restored.hudBarHiddenItems, floatingHidden)
        XCTAssertEqual(restored.codexProfiles, profiles)
        settings.menuBarVisibilityBinding(for: FloatingBarVisibility.antigravity).wrappedValue = true
        XCTAssertFalse(settings.menuBarPreferences.hiddenItems.contains(FloatingBarVisibility.antigravity))
        XCTAssertEqual(settings.menuBarPreferences.hiddenItems.count, 1)
    }

    func testOneAccountShowsSessionThenWeeklyWithItsVisualName() {
        let profile = UsageProfile(provider: .codex, name: "Codex")
        let items = MenuBarQuotaItem.items(profiles: [profile], snapshots: [profile.id: snapshot(profile)],
                                           claudeUsage: nil, preferences: MenuBarPreferences(quota: .weekly),
                                           displayNames: [profile.id: "Personal"], now: now, mode: .stackedBars)
        XCTAssertTrue(MenuBarQuotaItem.isSessionWeeklyPair(items))
        XCTAssertEqual(items.map(\.percent), [39, 88])
        XCTAssertEqual(items.map(\.label), ["Personal · Session (5h)", "Personal · Weekly"])
        XCTAssertEqual(Set(items.map(\.id)).count, 2)
        let tooltip = MenuBarQuotaItem.tooltip(items: items, quota: .weekly, mode: .stackedBars)
        XCTAssertTrue(tooltip.contains("Session (5h) + Weekly remaining"))
        XCTAssertTrue(tooltip.contains("Personal · Session (5h): 39%"))
        XCTAssertTrue(tooltip.contains("Personal · Weekly: 88%"))
    }

    func testOneProviderGroupsEachPeriodIndependentlyAcrossSelectedAccounts() {
        let personal = UsageProfile(provider: .codex, name: "Personal")
        let work = UsageProfile(provider: .codex, name: "Work")
        let ag = UsageProfile(provider: .antigravity, name: "Antigravity")
        let items = MenuBarQuotaItem.items(profiles: [personal, work, ag], snapshots: [
            personal.id: snapshot(personal), work.id: snapshot(work, session: 97, weekly: 87),
            ag.id: snapshot(ag, session: 1, weekly: 1)
        ], claudeUsage: nil, preferences: MenuBarPreferences(grouping: .providers,
                                                             hiddenItems: [FloatingBarVisibility.antigravity]),
        now: now, mode: .stackedBars)
        XCTAssertTrue(MenuBarQuotaItem.isSessionWeeklyPair(items))
        XCTAssertEqual(items.map(\.percent), [39, 87])
        XCTAssertEqual(items.map(\.label), ["Codex (Personal, Work) · Session (5h)",
                                           "Codex (Personal, Work) · Weekly"])
    }

    func testMultipleSelectionsAndPercentageStylesKeepChosenQuota() {
        let personal = UsageProfile(provider: .codex, name: "Personal")
        let work = UsageProfile(provider: .codex, name: "Work")
        let data = [personal.id: snapshot(personal), work.id: snapshot(work, weekly: 87)]
        let multiple = MenuBarQuotaItem.items(profiles: [personal, work], snapshots: data, claudeUsage: nil,
                                              preferences: MenuBarPreferences(quota: .weekly),
                                              now: now, mode: .stackedBars)
        XCTAssertFalse(MenuBarQuotaItem.isSessionWeeklyPair(multiple))
        XCTAssertEqual(multiple.map(\.percent), [88, 87])
        for mode in [MenuBarDisplayMode.stackedPercentages, .accountPercentages] {
            let single = MenuBarQuotaItem.items(profiles: [personal], snapshots: data, claudeUsage: nil,
                                                preferences: MenuBarPreferences(quota: .weekly), now: now, mode: mode)
            XCTAssertEqual(single.count, 1)
            XCTAssertEqual(single.first?.percent, 88)
        }
    }

    func testMissingWeeklyQuotaStaysUnavailableInItsOwnBar() {
        let profile = UsageProfile(provider: .codex, name: "Personal")
        let items = MenuBarQuotaItem.items(profiles: [profile], snapshots: [
            profile.id: UsageSnapshot(profileID: profile.id, windows: [
                UsageWindow(id: "session", label: "5 h", remainingPercent: 70, durationMinutes: 300),
                UsageWindow(id: "reserve", label: "7 days", remainingPercent: 100, durationMinutes: 10_080,
                            scope: "base_model_inference")
            ], fetchedAt: now)
        ], claudeUsage: nil, preferences: MenuBarPreferences(), now: now, mode: .stackedBars)
        XCTAssertTrue(MenuBarQuotaItem.isSessionWeeklyPair(items))
        XCTAssertEqual(items.map(\.percent), [70, nil])
        XCTAssertTrue(MenuBarQuotaItem.tooltip(items: items, quota: .fiveHours, mode: .stackedBars)
            .contains("Personal · Weekly: Unavailable"))
        XCTAssertTrue(MenuBarQuotaItem.items(profiles: [profile], snapshots: [:], claudeUsage: nil,
                                             preferences: MenuBarPreferences(hiddenItems: [profile.id.uuidString]),
                                             now: now, mode: .stackedBars).isEmpty)
    }

    func testCompactImagesStayWithinMenuBarHeightAndGrowByColumn() {
        _ = NSApplication.shared
        let items = (0..<8).map { MenuBarQuotaItem(id: "\($0)", label: "Account \($0)", percent: $0 * 10) }
        for mode in [MenuBarDisplayMode.stackedBars, .stackedPercentages] {
            for count in 0...8 {
                let image = MenuBarIndicators.image(items: Array(items.prefix(count)), mode: mode)
                XCTAssertTrue(image.isTemplate)
                XCTAssertLessThanOrEqual(image.size.height, 18)
                XCTAssertLessThanOrEqual(image.size.width, 120)
                XCTAssertNotNil(image.tiffRepresentation)
            }
        }
        XCTAssertEqual(MenuBarIndicators.image(items: Array(items.prefix(2)), mode: .stackedBars).size.width, 15)
        XCTAssertEqual(MenuBarIndicators.image(items: Array(items.prefix(2)), mode: .stackedPercentages).size.width, 27)
    }
}
