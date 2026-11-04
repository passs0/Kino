import Foundation

public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public var isSuccess: Bool { exitCode == 0 }
}

public enum ProcessError: LocalizedError, Sendable {
    case executableNotFound(String)
    case executionFailed(exitCode: Int32, stderr: String)
    case timedOut
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let name):
            return "Executable '\(name)' could not be located on the system."
        case .executionFailed(let code, let stderr):
            return "Command exited with status \(code): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .timedOut:
            return "Command execution timed out."
        case .cancelled:
            return "Command execution was cancelled."
        }
    }
}

/// Helper for asynchronous execution of CLI subprocesses with real-time streaming output.
public final class ProcessRunner: @unchecked Sendable {
    public static func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> ProcessResult {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw ProcessError.executableNotFound(executablePath)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments

            var env = ProcessInfo.processInfo.environment
            // Ensure managed Serein/bin, homebrew, and local bin are always in PATH for sub-commands
            let managedBin = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("Serein/bin").path ?? ""
            let extraPaths = "\(managedBin):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            env["PATH"] = "\(extraPaths):\(env["PATH"] ?? "")"
            if let customEnv = environment {
                for (k, v) in customEnv { env[k] = v }
            }
            process.environment = env

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            var stdoutData = Data()
            var stderrData = Data()
            let queue = DispatchQueue(label: "serein.process.io")

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty {
                    queue.sync { stdoutData.append(chunk) }
                }
            }

            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty {
                    queue.sync { stderrData.append(chunk) }
                }
            }

            process.terminationHandler = { p in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil

                queue.sync {
                    let outStr = String(data: stdoutData, encoding: .utf8) ?? ""
                    let errStr = String(data: stderrData, encoding: .utf8) ?? ""
                    continuation.resume(returning: ProcessResult(
                        exitCode: p.terminationStatus,
                        stdout: outStr,
                        stderr: errStr
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Spawns a streaming long-running process (e.g. FFmpeg) and delivers line callbacks.
    public static func spawnStreaming(
        executablePath: String,
        arguments: [String],
        environment: [String: String]? = nil,
        onOutput: (@Sendable (String) -> Void)? = nil,
        onError: (@Sendable (String) -> Void)? = nil
    ) throws -> Process {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw ProcessError.executableNotFound(executablePath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        var env = ProcessInfo.processInfo.environment
        let managedBin = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("Serein/bin").path ?? ""
        let extraPaths = "\(managedBin):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["PATH"] = "\(extraPaths):\(env["PATH"] ?? "")"
        if let customEnv = environment {
            for (k, v) in customEnv { env[k] = v }
        }
        process.environment = env

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe

        let outQueue = DispatchQueue(label: "serein.process.streaming.out")
        let errQueue = DispatchQueue(label: "serein.process.streaming.err")

        var outBuffer = ""
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) else { return }
            outQueue.async {
                outBuffer.append(text)
                while let nl = outBuffer.firstIndex(of: "\n") {
                    let line = String(outBuffer[..<nl])
                    outBuffer.removeSubrange(...nl)
                    onOutput?(line)
                }
            }
        }

        var errBuffer = ""
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) else { return }
            errQueue.async {
                errBuffer.append(text)
                while let nl = errBuffer.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
                    let line = String(errBuffer[..<nl])
                    errBuffer.removeSubrange(...nl)
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        onError?(trimmed)
                    }
                }
            }
        }

        try process.run()
        return process
    }
}
