import Foundation
import XCTest
@testable import SeeUsage

final class ProfilePresentationTests: XCTestCase {
    func testDisplayNamesRemainSeparateFromAccountsAndIdentity() {
        let personal = UsageProfile(provider: .codex, name: "Main", homePath: "/profiles/personal")
        let work = UsageProfile(provider: .codex, name: "Main", homePath: "/profiles/work")
        var preferences = ProfilePresentation()
        preferences.setDisplayName("Personal", for: personal.id)
        preferences.setDisplayName("Work", for: work.id)
        preferences.setCollapsed(true, for: work.id)
        XCTAssertEqual(preferences.displayName(for: personal.id, defaultName: personal.name), "Personal")
        XCTAssertEqual(preferences.displayName(for: work.id, defaultName: work.name), "Work")
        XCTAssertFalse(preferences.isCollapsed(personal.id))
        XCTAssertTrue(preferences.isCollapsed(work.id))
        XCTAssertEqual(personal.name, "Main")
        XCTAssertEqual(work.name, "Main")
        XCTAssertEqual(personal.homePath, "/profiles/personal")
        XCTAssertEqual(work.homePath, "/profiles/work")
        preferences.setDisplayName("Client account", for: work.id)
        XCTAssertTrue(preferences.isCollapsed(work.id))
    }

    func testResetNormalizationAndLongNames() {
        let id = UUID()
        var preferences = ProfilePresentation()
        XCTAssertEqual(preferences.displayName(for: id, defaultName: "Main"), "Main")
        preferences.setDisplayName("  Work\n  Account\t ", for: id)
        XCTAssertEqual(preferences.displayName(for: id, defaultName: "Main"), "Work Account")
        preferences.setDisplayName(String(repeating: "x", count: 100), for: id)
        XCTAssertEqual(preferences.displayNames[id]?.count, 60)
        preferences.setCollapsed(true, for: id)
        preferences.setDisplayName(" \n\t ", for: id)
        XCTAssertEqual(preferences.displayName(for: id, defaultName: "Main"), "Main")
        XCTAssertNil(preferences.displayNames[id])
        XCTAssertTrue(preferences.isCollapsed(id))
        preferences.setCollapsed(false, for: id)
        XCTAssertFalse(preferences.isCollapsed(id))
    }

    func testPreferencesPersistIndependentlyForAllProviders() throws {
        let first = UUID(), second = UUID()
        let antigravity = SettingsStore.antigravityProfileID
        let claude = ClaudeUsageSnapshot.profileID
        var preferences = ProfilePresentation()
        for (id, name) in [(first, "Personal"), (second, "Work"), (antigravity, "Models"), (claude, "Claude Pro")] {
            preferences.setDisplayName(name, for: id)
        }
        preferences.setCollapsed(true, for: antigravity)
        preferences.setCollapsed(true, for: second)
        let domain = "SeeUsagePresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(try JSONEncoder().encode(preferences), forKey: "profilePresentation")
        let reopened = try XCTUnwrap(UserDefaults(suiteName: domain))
        let restored = try JSONDecoder().decode(ProfilePresentation.self,
                                                from: XCTUnwrap(reopened.data(forKey: "profilePresentation")))
        XCTAssertEqual(restored, preferences)
        XCTAssertTrue(restored.isCollapsed(antigravity))
        XCTAssertFalse(restored.isCollapsed(first))
        XCTAssertFalse(restored.isCollapsed(claude))
    }

    func testDuplicateVisualNamesDoNotMergeFloatingBarAccounts() {
        let profiles = [UsageProfile(provider: .codex, name: "Main", homePath: "/personal"),
                        UsageProfile(provider: .codex, name: "Other", homePath: "/work")]
        var preferences = ProfilePresentation()
        for profile in profiles { preferences.setDisplayName("Same name", for: profile.id) }
        let date = Date()
        let snapshots = Dictionary(uniqueKeysWithValues: profiles.enumerated().map { index, profile in
            (profile.id, UsageSnapshot(profileID: profile.id,
                                      windows: [UsageWindow(id: "5h", label: "5 h", remainingPercent: Double(80 - index * 20),
                                                            durationMinutes: 300)], fetchedAt: date))
        })
        let items = FloatingQuotaItem.items(profiles: profiles, snapshots: snapshots, claudeUsage: nil,
                                            refreshIntervalMinutes: 5, displayNames: preferences.displayNames, now: date)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(Set(items.map(\.id)).count, 2)
        XCTAssertEqual(items.map(\.label), ["Same name", "Same name"])
        XCTAssertEqual(items.map { $0.values.first?.percent }, [80, 60])
        XCTAssertEqual(profiles.map(\.name), ["Main", "Other"])
    }

    @MainActor
    func testSettingsStoreRestoresPresentationWithoutChangingProviderConfiguration() throws {
        let domain = "SeeUsageSettingsPresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let settings = SettingsStore(presentationDefaults: defaults)
        let originalProfiles = settings.codexProfiles
        let originalOrder = settings.profileDisplayOrder
        let originalCodex = settings.codexExecutableOverride
        let id = originalProfiles.first?.id ?? UUID()
        settings.setDisplayName("Personal account", for: id)
        settings.setProfileCollapsed(true, for: SettingsStore.antigravityProfileID)
        let reopened = SettingsStore(presentationDefaults: defaults)
        XCTAssertEqual(reopened.displayName(for: id, defaultName: "Main"), "Personal account")
        XCTAssertTrue(reopened.profilePresentation.isCollapsed(SettingsStore.antigravityProfileID))
        XCTAssertEqual(settings.codexProfiles, originalProfiles)
        XCTAssertEqual(reopened.codexProfiles, originalProfiles)
        XCTAssertEqual(settings.profileDisplayOrder, originalOrder)
        XCTAssertEqual(settings.codexExecutableOverride, originalCodex)
        settings.setDisplayName("", for: id)
        XCTAssertEqual(settings.displayName(for: id, defaultName: "Main"), "Main")
    }

    @MainActor
    func testCollapsedSummarySeparatesPeriodsAndRejectsInvalidPercentages() {
        let windows = [UsageWindow(id: "short", label: "5 h", remainingPercent: 60, durationMinutes: 300),
                       UsageWindow(id: "week", label: "7 days", remainingPercent: 80, durationMinutes: 10_080),
                       UsageWindow(id: "other-week", label: "7 days", remainingPercent: 40, durationMinutes: 10_080),
                       UsageWindow(id: "bad", label: "5 h", remainingPercent: .nan, durationMinutes: 300)]
        XCTAssertEqual(AccountSectionHeader.quotaSummary(windows: windows), "5h 60% · 7d 40%")
        XCTAssertNil(AccountSectionHeader.quotaSummary(windows: []))
        XCTAssertEqual(AccountSectionHeader.quotaSummary(windows: Array(windows.prefix(1))), "5h 60%")
    }
}
