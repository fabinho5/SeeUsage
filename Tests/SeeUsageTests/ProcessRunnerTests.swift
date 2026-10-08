import XCTest
import Darwin
@testable import SeeUsage

final class ProcessRunnerTests: XCTestCase {
    func testSuccessfulExecution() async throws {
        let result = try await ProcessRunner.run(
            executable: "/bin/echo",
            arguments: ["hello world"],
            timeout: 5
        )
        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(result.outputString.trimmingCharacters(in: .whitespacesAndNewlines), "hello world")
    }

    func testNonZeroExit() async throws {
        let result = try await ProcessRunner.run(
            executable: "/usr/bin/false",
            arguments: [],
            timeout: 5
        )
        XCTAssertNotEqual(result.terminationStatus, 0)
    }

    func testTimeout() async {
        do {
            _ = try await ProcessRunner.run(
                executable: "/bin/sleep",
                arguments: ["5"],
                timeout: 0.5
            )
            XCTFail("Should have timed out")
        } catch let error as ProcessRunnerError {
            if case .timedOut = error {
                // Expected
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testExecutableResolution() {
        let echoPath = ProcessRunner.resolveExecutable(named: "echo")
        XCTAssertNotNil(echoPath)
        XCTAssertTrue(echoPath?.hasSuffix("/echo") == true)
    }

    func testInheritedPipesDoNotHangAfterParentExits() async throws {
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent("SeeUsageFakeChild-\(UUID())")
        defer {
            if let text = try? String(contentsOf: pidFile, encoding: .utf8),
               let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                _ = kill(pid, SIGTERM)
            }
            try? FileManager.default.removeItem(at: pidFile)
        }
        let started = Date()
        let result = try await ProcessRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "/bin/sleep 5 & printf '%s' $! > \"$1\"; printf 'done'; exit 0", "fixture", pidFile.path],
            timeout: 2
        )
        XCTAssertEqual(result.outputString, "done")
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5)
    }

    func testFragmentedResponseAndMatchingServerRequestDoNotEndProcessEarly() async throws {
        let result = try await ProcessRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", #"printf '%s\n' '{"id":3,"method":"fake/server/request"}'; printf '%s' '{"id":3,"result":'; /bin/sleep 0.1; printf '%s\n' '{"outcome":"fake"}}'"#],
            timeout: 3,
            completionResponseID: 3
        )
        XCTAssertTrue(result.outputString.contains(#"{"id":3,"result":{"outcome":"fake"}}"#))
    }
}
