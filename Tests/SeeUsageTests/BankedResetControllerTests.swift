import XCTest
@testable import SeeUsage

@MainActor
final class BankedResetControllerTests: XCTestCase {
    private let profile = UsageProfile(provider: .codex, name: "Original", homePath: "/tmp/fake-codex-profile")
    private let credit = BankedResetCredit(id: "display-id", serverCreditID: "fake-server-credit")

    func testCancelNeverSendsResetAndAllowsAnotherConfirmation() async throws {
        var confirmations: [String] = []
        let controller = BankedResetController(confirm: { name in
            confirmations.append(name)
            return false
        }, consume: { _, _ in
            XCTFail("Cancelling must never send a reset request")
            return (false, "Unexpected")
        }, showResult: { _ in XCTFail("Cancel must not show a reset result") })

        for _ in 0..<2 {
            let task = try XCTUnwrap(controller.request(profile: profile, credit: credit, displayName: "Personal"))
            await task.value
            XCTAssertNil(controller.activeProfileID)
        }
        XCTAssertEqual(confirmations, ["Personal", "Personal"])
    }

    func testDuplicateClicksCannotSendTwoResetsAndSecondAttemptWorksAfterFailure() async throws {
        var calls: [(UUID, String?)] = []
        var messages: [String] = []
        let controller = BankedResetController(confirm: { _ in true }, consume: { profile, creditID in
            calls.append((profile.id, creditID))
            await Task.yield()
            return (false, "Mock timeout")
        }, showResult: { messages.append($0) })

        let first = try XCTUnwrap(controller.request(profile: profile, credit: credit, displayName: "Personal"))
        XCTAssertEqual(controller.activeProfileID, profile.id)
        XCTAssertNil(controller.request(profile: profile, credit: credit, displayName: "Duplicate"))
        await first.value
        XCTAssertNil(controller.activeProfileID)
        XCTAssertEqual(calls.count, 1, "A failed attempt must not retry automatically")

        let second = try XCTUnwrap(controller.request(profile: profile, credit: credit, displayName: "Personal"))
        await second.value
        XCTAssertEqual(calls.map(\.0), [profile.id, profile.id])
        XCTAssertEqual(calls.compactMap(\.1), ["fake-server-credit", "fake-server-credit"])
        XCTAssertEqual(messages, ["Mock timeout", "Mock timeout"])
        XCTAssertNil(controller.activeProfileID)
    }

    func testCountOnlyCreditDoesNotSendSyntheticIdentifier() async throws {
        var invoked = false
        let controller = BankedResetController(confirm: { _ in true }, consume: { _, creditID in
            invoked = true
            XCTAssertNil(creditID)
            return (true, "Mock reset")
        }, showResult: { XCTAssertEqual($0, "Mock reset") })
        let countOnly = BankedResetCredit(id: "count-only-fake")
        let task = try XCTUnwrap(controller.request(profile: profile, credit: countOnly, displayName: "Personal"))
        await task.value
        XCTAssertTrue(invoked)
        XCTAssertNil(controller.activeProfileID)
    }
}
