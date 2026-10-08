import Foundation
import XCTest
@testable import SeeUsage

/// Every request goes to a temporary shell fixture. These tests never resolve or launch Codex.
final class CodexResetTests: XCTestCase {
    private struct FakeServer {
        let folder: URL
        var executable: URL { folder.appendingPathComponent("fake-codex.sh") }
        var requests: URL { folder.appendingPathComponent("requests.jsonl") }

        init(response: String, initialization: String = #"{"id":1,"result":{}}"#,
             checkOrdering: Bool = true, delayResponse: Bool = false) throws {
            folder = FileManager.default.temporaryDirectory.appendingPathComponent("SeeUsageFakeCodex-\(UUID())")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            func quoted(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }
            let ordering = checkOrdering ? """
            if IFS= read -r -t 1 early; then
                printf '%s\\n' '{"id":3,"error":{"message":"Request sent before initialization"}}'
                exit 0
            fi
            """ : ""
            let script = """
            #!/bin/bash
            IFS= read -r initial
            printf '%s\\n' "$initial" >> \(quoted(requests.path))
            \(ordering)
            printf '%s\\n' \(quoted(initialization))
            IFS= read -r initialized || exit 0
            printf '%s\\n' "$initialized" >> \(quoted(requests.path))
            IFS= read -r request || exit 0
            printf '%s\\n' "$request" >> \(quoted(requests.path))
            \(delayResponse ? "/bin/sleep 3" : "")
            printf '%s\\n' \(quoted(response))
            """
            try script.write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        }

        func inputMessages() throws -> [[String: Any]] {
            try String(contentsOf: requests, encoding: .utf8).split(separator: "\n").map {
                try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
            }
        }

        func remove() { try? FileManager.default.removeItem(at: folder) }
    }

    private let profile = UsageProfile(provider: .codex, name: "Fake", homePath: "/tmp/fake-codex-profile")

    func testWaitsForInitializationAndSendsOnlySelectedCreditOnce() async throws {
        let server = try FakeServer(response: #"{"id":3,"result":{"outcome":"reset"}}"#)
        defer { server.remove() }
        let result = await CodexClient.consumeResetCredit(profile: profile, creditId: "fake-credit", executable: server.executable.path, timeout: 5)
        XCTAssertTrue(result.success, result.message)
        let messages = try server.inputMessages()
        XCTAssertEqual(messages.compactMap { $0["method"] as? String }, ["initialize", "initialized", "account/rateLimitResetCredit/consume"])
        let params = try XCTUnwrap(messages.last?["params"] as? [String: Any])
        XCTAssertEqual(params["creditId"] as? String, "fake-credit")
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(params["idempotencyKey"] as? String)))
    }

    func testInitializationErrorNeverSendsConsumeRequest() async throws {
        let server = try FakeServer(response: "", initialization: #"{"id":1,"error":{"message":"Mock initialization failure"}}"#)
        defer { server.remove() }
        let result = await CodexClient.consumeResetCredit(profile: profile, creditId: "fake-credit", executable: server.executable.path, timeout: 5)
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.message.contains("Mock initialization failure"), result.message)
        XCTAssertEqual(try server.inputMessages().count, 1)
    }

    func testQuotaRefreshUsesTheAcknowledgedHandshakeToo() async throws {
        let server = try FakeServer(response: #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":23,"windowDurationMins":300}}}}"#)
        defer { server.remove() }
        let snapshot = await CodexClient.fetch(profile: profile, executable: server.executable.path, timeout: 5)
        XCTAssertNil(snapshot.error)
        XCTAssertEqual(snapshot.windows.first?.remainingPercent, 77)
        XCTAssertEqual(try server.inputMessages().compactMap { $0["method"] as? String }, ["initialize", "initialized", "account/rateLimits/read"])
    }

    func testCountOnlyAndServerOutcomes() async throws {
        for (outcome, success) in [("alreadyRedeemed", true), ("nothingToReset", false), ("noCredit", false), ("unknown", false)] {
            let server = try FakeServer(response: "{\"id\":3,\"result\":{\"outcome\":\"\(outcome)\"}}", checkOrdering: false)
            defer { server.remove() }
            let result = await CodexClient.consumeResetCredit(profile: profile, creditId: nil, executable: server.executable.path, timeout: 5)
            XCTAssertEqual(result.success, success, result.message)
            let params = try XCTUnwrap(try server.inputMessages().last?["params"] as? [String: Any])
            XCTAssertNil(params["creditId"])
        }
    }

    func testBackendErrorAndMissingOutcomeAreNotSuccess() async throws {
        for response in [#"{"id":3,"error":{"message":"Mock backend error"}}"#, #"{"id":3,"result":{}}"#] {
            let server = try FakeServer(response: response, checkOrdering: false)
            defer { server.remove() }
            let result = await CodexClient.consumeResetCredit(profile: profile, creditId: "fake-credit", executable: server.executable.path, timeout: 5)
            XCTAssertFalse(result.success)
        }
    }

    func testTimeoutDoesNotRetryConsume() async throws {
        let server = try FakeServer(response: #"{"id":3,"result":{"outcome":"reset"}}"#, checkOrdering: false, delayResponse: true)
        defer { server.remove() }
        let started = Date()
        let result = await CodexClient.consumeResetCredit(profile: profile, creditId: "fake-credit", executable: server.executable.path, timeout: 1)
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.message, "Operation timed out.")
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        let methods = try server.inputMessages().compactMap { $0["method"] as? String }
        XCTAssertEqual(methods.filter { $0 == "account/rateLimitResetCredit/consume" }.count, 1)
    }
}
