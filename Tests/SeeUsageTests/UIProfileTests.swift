import AppKit
import SwiftUI
import XCTest
@testable import SeeUsage

final class UIProfileTests: XCTestCase {
    func testExistingInstallationsAndUnknownProfilesUseCompact() throws {
        let domain = "SeeUsageUIProfileTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        XCTAssertEqual(SettingsStore(presentationDefaults: defaults).uiProfile, .compact)
        defaults.set("future-profile", forKey: "uiProfile")
        XCTAssertEqual(SettingsStore(presentationDefaults: defaults).uiProfile, .compact)
    }

    func testSwitchingAndRestartingPreserveSharedAccountPreferences() throws {
        let domain = "SeeUsageUIProfileTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let settings = SettingsStore(presentationDefaults: defaults)
        let account = settings.codexProfiles.first?.id ?? UUID()
        settings.setDisplayName("Personal", for: account)
        settings.setProfileCollapsed(true, for: SettingsStore.antigravityProfileID)
        let presentation = settings.profilePresentation
        let profiles = settings.codexProfiles
        let order = settings.profileDisplayOrder
        let theme = settings.selectedThemeID
        let refresh = settings.refreshIntervalMinutes
        let executable = settings.codexExecutableOverride
        let hudEnabled = settings.hudEnabled
        let quotas = settings.hudBarQuotas
        let notifications = settings.notificationsEnabled

        for profile in [UIProfile.classic, .compact, .classic] {
            settings.uiProfile = profile
            let restored = SettingsStore(presentationDefaults: defaults)
            XCTAssertEqual(restored.uiProfile, profile)
            XCTAssertEqual(restored.profilePresentation, presentation)
            XCTAssertEqual(restored.codexProfiles, profiles)
            XCTAssertEqual(restored.profileDisplayOrder, order)
            XCTAssertEqual(restored.selectedThemeID, theme)
            XCTAssertEqual(restored.refreshIntervalMinutes, refresh)
            XCTAssertEqual(restored.codexExecutableOverride, executable)
            XCTAssertEqual(restored.hudEnabled, hudEnabled)
            XCTAssertEqual(restored.hudBarQuotas, quotas)
            XCTAssertEqual(restored.notificationsEnabled, notifications)
        }
        // Edits made in Classic are also visible after switching back to Compact.
        settings.setDisplayName("Work", for: account)
        settings.setProfileCollapsed(false, for: SettingsStore.antigravityProfileID)
        settings.uiProfile = .compact
        XCTAssertEqual(settings.displayName(for: account, defaultName: "Main"), "Work")
        XCTAssertFalse(settings.profilePresentation.isCollapsed(SettingsStore.antigravityProfileID))
    }

    @MainActor
    func testNativePopoverViewResizesWhenProfileChanges() throws {
        _ = NSApplication.shared
        let domain = "SeeUsageUILayoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let settings = SettingsStore(presentationDefaults: defaults)
        let host = NSHostingView(rootView: UsagePopoverView(settings: settings))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: settings.uiProfile.popoverSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        for profile in [UIProfile.compact, .classic, .compact] {
            settings.uiProfile = profile
            window.setContentSize(profile.popoverSize)
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.fittingSize.width, profile.popoverSize.width, accuracy: 1)
            XCTAssertEqual(host.fittingSize.height, profile.popoverSize.height, accuracy: 1)
        }
    }
}
