import AppKit
import XCTest
@testable import SeeUsage

@MainActor
final class CompanionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFirstReadingSetsAppearanceWithoutInventingDamage() {
        var tracker = CompanionQuotaTracker()
        let update = tracker.update([reading(12)], now: now)
        XCTAssertEqual(update.look, .critical)
        XCTAssertEqual(update.remainingPercent, 12)
        XCTAssertEqual(update.reaction, .none)
    }

    func testFreshUnchangedQuotasCelebrate() {
        var tracker = CompanionQuotaTracker()
        _ = tracker.update([reading(80, seconds: -300)], now: now)
        XCTAssertEqual(tracker.update([reading(80)], now: now).reaction, .celebrate)
    }

    func testDamageIsProportionalAndDoesNotDoubleCountFiveHourAndWeeklyUsage() {
        var tracker = CompanionQuotaTracker()
        _ = tracker.update([reading(80, seconds: -300), reading(90, window: "weekly", seconds: -300)], now: now)
        let update = tracker.update([reading(68), reading(78, window: "weekly")], now: now)
        XCTAssertEqual(update.reaction, .damage(12))
        XCTAssertEqual(update.remainingPercent, 68)
    }

    func testDamageIsDetectedWhenGlobalMinimumIncreases() {
        var tracker = CompanionQuotaTracker()
        _ = tracker.update([reading(15, source: "personal", seconds: -300),
                            reading(80, source: "work", seconds: -300)], now: now)
        let update = tracker.update([reading(25, source: "personal"), reading(75, source: "work")], now: now)
        XCTAssertEqual(update.reaction, .damage(5))
        XCTAssertEqual(update.remainingPercent, 25)
    }

    func testAddingAndRemovingProfilesDoesNotInventDamageOrCelebrations() {
        var tracker = CompanionQuotaTracker()
        _ = tracker.update([reading(90, seconds: -300)], now: now)
        XCTAssertEqual(tracker.update([reading(90), reading(5, source: "new")], now: now).reaction, .none)
        XCTAssertEqual(tracker.update([reading(90, seconds: 300)], now: now).reaction, .none)
    }

    func testChangingWindowIdentityStartsANewBaseline() {
        var tracker = CompanionQuotaTracker()
        _ = tracker.update([reading(90, window: "5h", seconds: -300)], now: now)
        XCTAssertEqual(tracker.update([reading(10, window: "weekly")], now: now).reaction, .none)
    }

    func testResetDoesNotTreatConsumptionInANewCycleAsOldCycleDamage() {
        var tracker = CompanionQuotaTracker()
        _ = tracker.update([reading(90, seconds: -300, resetsAt: now.addingTimeInterval(60))], now: now)
        let update = tracker.update([reading(25, resetsAt: now.addingTimeInterval(18_000))], now: now)
        XCTAssertEqual(update.reaction, .celebrate)
    }

    func testDuplicateCacheNotificationsDoNotCelebrateOrRepeatDamage() {
        var tracker = CompanionQuotaTracker()
        _ = tracker.update([reading(90, seconds: -300)], now: now)
        XCTAssertEqual(tracker.update([reading(85)], now: now).reaction, .damage(5))
        XCTAssertEqual(tracker.update([reading(85)], now: now).reaction, .none)
    }

    func testOlderCacheCannotReplaceTheBaseline() {
        var tracker = CompanionQuotaTracker()
        _ = tracker.update([reading(90)], now: now)
        let old = tracker.update([reading(10, seconds: -300)], now: now)
        XCTAssertEqual(old.reaction, .none)
        XCTAssertEqual(old.remainingPercent, 90)
        XCTAssertEqual(tracker.update([reading(88, seconds: 300)], now: now).reaction, .damage(2))
    }

    func testMissingDataDoesNotCelebrateAndRecoveryStartsANewBaseline() {
        var tracker = CompanionQuotaTracker()
        _ = tracker.update([reading(90, seconds: -300)], now: now)
        let missing = tracker.update([], now: now)
        XCTAssertEqual(missing.look, .unavailable)
        XCTAssertEqual(missing.reaction, .none)
        XCTAssertEqual(tracker.update([reading(40)], now: now).reaction, .none)
    }

    func testCollectionRejectsFailedStaleExpiredAndInvalidReadings() {
        let profiles = (0..<5).map { UsageProfile(provider: .codex, name: "\($0)") }
        func window(_ percent: Double?, reset: Date? = nil) -> UsageWindow {
            UsageWindow(id: "5h", label: "5h", remainingPercent: percent, durationMinutes: 300, resetsAt: reset)
        }
        let snapshots = [
            profiles[0].id: UsageSnapshot(profileID: profiles[0].id, windows: [window(90)], fetchedAt: now, error: "Failed"),
            profiles[1].id: UsageSnapshot(profileID: profiles[1].id, windows: [window(90)], fetchedAt: now.addingTimeInterval(-601)),
            profiles[2].id: UsageSnapshot(profileID: profiles[2].id, windows: [window(90, reset: now)], fetchedAt: now),
            profiles[3].id: UsageSnapshot(profileID: profiles[3].id, windows: [window(.nan), window(.infinity), window(nil)], fetchedAt: now),
            profiles[4].id: UsageSnapshot(profileID: profiles[4].id, windows: [window(95)], fetchedAt: now)
        ]
        let readings = CompanionQuotaReading.collect(profiles: profiles, snapshots: snapshots,
            claudeUsage: ClaudeUsageSnapshot(updatedAt: now.addingTimeInterval(-601), windows: [window(10)]), now: now)
        XCTAssertEqual(readings.count, 1)
        XCTAssertEqual(readings.first?.remainingPercent, 95)
    }

    func testClaudeAndModelScopesHaveIndependentIdentities() {
        let profile = UsageProfile(provider: .antigravity, name: "Antigravity")
        let windows = ["Gemini", "Claude"].map {
            UsageWindow(id: "5h", label: "5h", remainingPercent: 80, durationMinutes: 300, scope: $0)
        }
        let readings = CompanionQuotaReading.collect(profiles: [profile],
            snapshots: [profile.id: UsageSnapshot(profileID: profile.id, windows: windows, fetchedAt: now)],
            claudeUsage: ClaudeUsageSnapshot(updatedAt: now, windows: [windows[1]]), now: now)
        XCTAssertEqual(Set(readings.map(\.id)).count, 3)
    }

    func testAppearanceFollowsRemainingQuota() {
        XCTAssertEqual(CompanionLook(remainingPercent: 100), .healthy)
        XCTAssertEqual(CompanionLook(remainingPercent: 40), .healthy)
        XCTAssertEqual(CompanionLook(remainingPercent: 39), .worn)
        XCTAssertEqual(CompanionLook(remainingPercent: 15), .worn)
        XCTAssertEqual(CompanionLook(remainingPercent: 0), .critical)
        XCTAssertEqual(CompanionLook(remainingPercent: nil), .unavailable)
    }

    func testMovementDoesNotOvershootOrTeleportAfterSleep() {
        let origin = NSPoint(x: 0, y: 0)
        XCTAssertEqual(CompanionMotion.advance(origin, toward: NSPoint(x: 1, y: 0), elapsed: 1), NSPoint(x: 1, y: 0))
        let afterSleep = CompanionMotion.advance(origin, toward: NSPoint(x: 1000, y: 0), elapsed: 3600)
        XCTAssertTrue(afterSleep.x <= 3.6)
        XCTAssertEqual(CompanionMotion.advance(origin, toward: origin, elapsed: 1), origin)
        XCTAssertEqual(CompanionMotion.advance(origin, toward: NSPoint(x: 10, y: 0), elapsed: .nan), origin)
    }

    func testMovementFitsAMonitorWithNegativeCoordinates() {
        let screen = NSRect(x: -1920, y: -200, width: 1920, height: 1080)
        let size = CompanionManager.panelSize
        for origin in [NSPoint(x: -3000, y: -500), NSPoint(x: 100, y: 2000)] {
            let clamped = CompanionMotion.clamp(origin, size: size, to: screen)
            XCTAssertTrue(screen.contains(NSRect(origin: clamped, size: size)))
        }
    }

    func testSubpixelMovementAccumulatesInANativePanel() {
        _ = NSApplication.shared
        let size = CompanionManager.panelSize
        let start = NSPoint(x: 1000, y: 100)
        let target = NSPoint(x: 500, y: 600)
        let screen = NSRect(x: 0, y: 0, width: 1700, height: 1000)
        let panel = NSPanel(contentRect: NSRect(origin: start, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        var motion = CompanionMotion(origin: start)
        for _ in 0..<30 {
            panel.setFrameOrigin(motion.step(toward: target, elapsed: 1.0 / 30, size: size, screen: screen))
        }
        XCTAssertTrue(panel.frame.minX < start.x - 10)
        XCTAssertTrue(panel.frame.minY > start.y + 10)
        panel.close()
    }

    func testAllAnimationStatesShipTransparentArtwork() {
        for name in CompanionArtwork.names {
            let image = CompanionArtwork.image(name)
            XCTAssertTrue(image.size.width >= 100)
            let bitmap = image.representations.compactMap { $0 as? NSBitmapImageRep }.first
            XCTAssertNotNil(bitmap)
            XCTAssertTrue(bitmap?.hasAlpha == true)
            XCTAssertEqual(bitmap?.colorAt(x: 0, y: 0)?.alphaComponent, 0)
        }
    }

    func testRefreshLoopStopsWhenHiddenAndNeverOverlaps() async throws {
        var checks = 0
        var active = 0
        var peakActive = 0
        let loop = CompanionRefreshLoop(interval: .milliseconds(5)) {
            checks += 1
            active += 1
            peakActive = max(peakActive, active)
            try? await Task.sleep(for: .milliseconds(10))
            active -= 1
        }
        for _ in 0..<30 {
            if checks >= 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(checks >= 2)
        loop.stop()
        let atStop = checks
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(checks, atStop)
        XCTAssertEqual(peakActive, 1)
    }

    private func reading(_ percent: Double, source: String = "personal", window: String = "5h",
                         seconds: TimeInterval = 0, resetsAt: Date? = nil) -> CompanionQuotaReading {
        CompanionQuotaReading(id: .init(source: source, window: window, scope: nil, durationMinutes: 300),
                              remainingPercent: percent, observedAt: now.addingTimeInterval(seconds), resetsAt: resetsAt)
    }
}
