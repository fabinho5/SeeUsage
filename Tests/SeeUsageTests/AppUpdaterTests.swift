import XCTest
@testable import SeeUsage

@MainActor
final class AppUpdaterTests: XCTestCase {
    func testLaunchChecksOnlyOnceAndNeverInstalls() {
        let backend = FakeUpdateBackend()
        let updater = AppUpdater(backend: backend)
        updater.start()
        updater.start()
        XCTAssertEqual(backend.starts, 1)
        XCTAssertEqual(backend.backgroundChecks, 1)
        XCTAssertEqual(backend.manualChecks, 0)
    }

    func testOptOutSurvivesLaunchAndManualCheckStillWorks() {
        let backend = FakeUpdateBackend()
        backend.automaticallyChecksForUpdates = false
        let updater = AppUpdater(backend: backend)
        updater.start()
        XCTAssertEqual(backend.backgroundChecks, 0)
        updater.checkForUpdates()
        XCTAssertEqual(backend.manualChecks, 1)
        updater.setAutomaticChecks(true)
        XCTAssertTrue(backend.automaticallyChecksForUpdates)
        XCTAssertTrue(updater.automaticallyChecksForUpdates)
        updater.setAutomaticChecks(false)
        XCTAssertFalse(updater.automaticallyChecksForUpdates)
    }

    func testBusyUpdateDisablesDuplicateChecksAndObservesPreferences() {
        let backend = FakeUpdateBackend()
        let updater = AppUpdater(backend: backend)
        updater.start()
        backend.canCheckForUpdates = false
        backend.stateChanged?()
        XCTAssertFalse(updater.canCheckForUpdates)
        updater.checkForUpdates()
        XCTAssertEqual(backend.manualChecks, 0)
        backend.canCheckForUpdates = true
        backend.automaticallyChecksForUpdates = false
        backend.stateChanged?()
        XCTAssertTrue(updater.canCheckForUpdates)
        XCTAssertFalse(updater.automaticallyChecksForUpdates)
        updater.checkForUpdates()
        XCTAssertEqual(backend.manualChecks, 1)
    }

    func testFailedStartupDoesNotScheduleOrAllowChecks() {
        let backend = FakeUpdateBackend()
        backend.failStartup = true
        let updater = AppUpdater(backend: backend)
        updater.start()
        updater.checkForUpdates()
        updater.start()
        XCTAssertNotNil(updater.errorMessage)
        XCTAssertFalse(updater.canCheckForUpdates)
        updater.setAutomaticChecks(false)
        XCTAssertFalse(updater.canCheckForUpdates, "A preference change cannot recover failed startup")
        XCTAssertEqual(backend.starts, 1)
        XCTAssertEqual(backend.backgroundChecks, 0)
        XCTAssertEqual(backend.manualChecks, 0)
    }

    func testSourceBuildOpensReleasesWithoutStartingAnUpdater() {
        var opens = 0
        let updater = AppUpdater(backend: nil, openReleases: { opens += 1 })
        updater.start()
        updater.setAutomaticChecks(true)
        XCTAssertFalse(updater.supportsInAppUpdates)
        XCTAssertFalse(updater.automaticallyChecksForUpdates)
        updater.checkForUpdates()
        XCTAssertEqual(opens, 1)
    }
}

@MainActor
private final class FakeUpdateBackend: AppUpdateBackend {
    var automaticallyChecksForUpdates = true
    var canCheckForUpdates = true
    var stateChanged: (() -> Void)?
    var failStartup = false
    var starts = 0
    var backgroundChecks = 0
    var manualChecks = 0
    func start() throws {
        starts += 1
        if failStartup { throw NSError(domain: "MockUpdate", code: 1) }
    }
    func checkInBackground() { backgroundChecks += 1 }
    func checkForUpdates() { manualChecks += 1 }
}
