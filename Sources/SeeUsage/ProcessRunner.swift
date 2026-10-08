import Foundation
import Darwin

public struct ProcessResult: Sendable {
    public let standardOutput: Data
    public let standardError: Data
    public let terminationStatus: Int32

    public var outputString: String {
        String(decoding: standardOutput, as: UTF8.self)
    }

    public var errorString: String {
        String(decoding: standardError, as: UTF8.self)
    }
}

public enum ProcessRunnerError: LocalizedError, Sendable {
    case executableNotFound(String)
    case timedOut(String)
    case launchFailed(String)
    case protocolFailure(String)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let name):
            return "\(name) CLI not found."
        case .timedOut:
            return "Operation timed out."
        case .launchFailed(let name):
            return "Failed to launch \(name)."
        case .protocolFailure(let message):
            return message
        }
    }
}

public struct ProcessHandshake: Sendable {
    public let input: Data
    public let responseID: Int

    public init(input: Data, responseID: Int) {
        self.input = input
        self.responseID = responseID
    }
}

public enum ProcessRunner {
    public static func defaultEnvironment(suppressColor: Bool = true) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let standardPaths = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "\(home)/.local/bin",
            "\(home)/bin",
            "/opt/anaconda3/bin",
            "/opt/anaconda3/condabin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "\(home)/.bun/bin",
            "\(home)/.volta/bin",
            "\(home)/.cargo/bin"
        ]

        var currentPaths = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        for p in standardPaths {
            if !currentPaths.contains(p) {
                currentPaths.append(p)
            }
        }

        env["PATH"] = currentPaths.joined(separator: ":")
        env["HOME"] = home
        if suppressColor { env["NO_COLOR"] = "1" }
        return env
    }

    public static func resolveExecutable(named name: String, overridePath: String? = nil) -> String? {
        let fm = FileManager.default
        if let override = overridePath?.trimmingCharacters(in: .whitespaces), !override.isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            if fm.isExecutableFile(atPath: expanded) {
                return expanded
            }
            if override.contains("/") {
                return nil
            }
            return findInKnownPaths(named: override)
        }

        return findInKnownPaths(named: name)
    }

    private static func findInKnownPaths(named name: String) -> String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var candidates: [String] = []

        let env = defaultEnvironment()
        if let pathEnv = env["PATH"] {
            for dir in pathEnv.split(separator: ":").map(String.init) {
                candidates.append("\(dir)/\(name)")
            }
        }

        let knownDirs = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "/usr/bin",
            "/bin",
            "\(home)/.bun/bin",
            "\(home)/.volta/bin",
            "\(home)/.asdf/shims",
            "\(home)/.local/share/mise/shims"
        ]

        for dir in knownDirs {
            candidates.append("\(dir)/\(name)")
        }

        for candidate in candidates {
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    public static func run(
        executable: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        input: Data? = nil,
        timeout: TimeInterval = 15,
        completionResponseID: Int? = nil,
        handshake: ProcessHandshake? = nil,
        suppressColor: Bool = true
    ) async throws -> ProcessResult {
        try await Task.detached(priority: .userInitiated) {
            try runSynchronous(
                executable: executable,
                arguments: arguments,
                environment: environment,
                input: input,
                timeout: timeout,
                completionResponseID: completionResponseID,
                handshake: handshake,
                suppressColor: suppressColor
            )
        }.value
    }

    private static func runSynchronous(
        executable: String,
        arguments: [String],
        environment: [String: String],
        input: Data?,
        timeout: TimeInterval,
        completionResponseID: Int?,
        handshake: ProcessHandshake?,
        suppressColor: Bool
    ) throws -> ProcessResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        let semaphore = DispatchSemaphore(value: 0)

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        var env = defaultEnvironment(suppressColor: suppressColor)
        environment.forEach { env[$0.key] = $0.value }
        process.environment = env

        // Read only bytes currently available. Waiting for pipe EOF can hang when
        // an app-server child inherits stdout/stderr, even after the parent exits.
        func stopProcess() {
            if process.isRunning {
                process.terminate()
                if semaphore.wait(timeout: .now() + .milliseconds(300)) == .timedOut {
                    if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
                    _ = semaphore.wait(timeout: .now() + .milliseconds(300))
                }
            }
        }
        defer {
            try? stdinPipe.fileHandleForWriting.close()
            stopProcess()
            try? stdoutPipe.fileHandleForReading.close()
            try? stderrPipe.fileHandleForReading.close()
        }
        process.terminationHandler = { _ in semaphore.signal() }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(executable)
        }

        let stdoutFD = stdoutPipe.fileHandleForReading.fileDescriptor
        let stderrFD = stderrPipe.fileHandleForReading.fileDescriptor
        for fd in [stdoutFD, stderrFD] {
            let flags = fcntl(fd, F_GETFL)
            guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0 else {
                throw ProcessRunnerError.protocolFailure("Unable to configure process output.")
            }
        }
        var stdoutData = Data()
        var stderrData = Data()
        var responses = JSONRPCResponseReader(ids: Set([completionResponseID, handshake?.responseID].compactMap { $0 }))
        var waitingForInitialization = handshake != nil
        var stdoutClosed = false
        var stderrClosed = false

        if let handshake {
            try stdinPipe.fileHandleForWriting.write(contentsOf: handshake.input)
        } else if let input {
            try stdinPipe.fileHandleForWriting.write(contentsOf: input)
        }
        if handshake == nil && (completionResponseID == nil || input == nil) {
            try? stdinPipe.fileHandleForWriting.close()
        }

        while true {
            let output = try readAvailable(from: stdoutFD)
            stdoutData.append(output.data)
            responses.append(output.data)
            stdoutClosed = stdoutClosed || output.closed
            let errors = try readAvailable(from: stderrFD)
            stderrData.append(errors.data)
            stderrClosed = stderrClosed || errors.closed

            if waitingForInitialization, let handshake,
               let response = responses.received[handshake.responseID] {
                if let error = response["error"] as? [String: Any] {
                    let message = error["message"] as? String ?? "Unknown initialization error."
                    throw ProcessRunnerError.protocolFailure("Server initialization failed: \(message)")
                }
                guard response["result"] is [String: Any] else {
                    throw ProcessRunnerError.protocolFailure("Server returned an invalid initialization response.")
                }
                waitingForInitialization = false
                if let input { try stdinPipe.fileHandleForWriting.write(contentsOf: input) }
                if completionResponseID == nil || input == nil {
                    try? stdinPipe.fileHandleForWriting.close()
                }
            }
            if let completionResponseID, responses.received[completionResponseID] != nil {
                break
            }
            if !process.isRunning {
                responses.finish()
                if waitingForInitialization {
                    throw ProcessRunnerError.protocolFailure("Server exited before initialization completed.")
                }
                break
            }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw ProcessRunnerError.timedOut(executable) }
            var descriptors = [
                pollfd(fd: stdoutClosed ? -1 : stdoutFD, events: Int16(POLLIN), revents: 0),
                pollfd(fd: stderrClosed ? -1 : stderrFD, events: Int16(POLLIN), revents: 0)
            ]
            let waitMilliseconds = Int32(min(50, max(1, remaining * 1_000)))
            _ = poll(&descriptors, 2, waitMilliseconds)
        }

        stopProcess()
        // Drain buffered output without waiting for inherited pipe handles to close.
        stdoutData.append(try readAvailable(from: stdoutFD).data)
        stderrData.append(try readAvailable(from: stderrFD).data)
        return ProcessResult(
            standardOutput: stdoutData,
            standardError: stderrData,
            terminationStatus: process.isRunning ? -1 : process.terminationStatus
        )
    }

    private static func readAvailable(from fd: Int32) throws -> (data: Data, closed: Bool) {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        // Bound each drain so continuous output cannot prevent deadline checks.
        for _ in 0..<16 {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count > 0 {
                data.append(contentsOf: buffer.prefix(count))
            } else if count == 0 {
                return (data, true)
            } else if errno == EINTR {
                continue
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                break
            } else {
                throw ProcessRunnerError.protocolFailure("Unable to read process output.")
            }
        }
        return (data, false)
    }
}

private struct JSONRPCResponseReader {
    let ids: Set<Int>
    private var lineBuffer = Data()
    private(set) var received: [Int: [String: Any]] = [:]

    init(ids: Set<Int>) { self.ids = ids }

    mutating func append(_ chunk: Data) {
        guard !ids.isEmpty else { return }
        lineBuffer.append(chunk)
        while let newline = lineBuffer.firstIndex(of: 0x0A) {
            record(Data(lineBuffer.prefix(upTo: newline)))
            lineBuffer.removeSubrange(...newline)
        }
    }

    mutating func finish() {
        if !lineBuffer.isEmpty { record(lineBuffer) }
        lineBuffer.removeAll()
    }

    private mutating func record(_ line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let id = object["id"] as? Int, ids.contains(id),
              object["result"] != nil || object["error"] != nil else { return }
        received[id] = object
    }
}
