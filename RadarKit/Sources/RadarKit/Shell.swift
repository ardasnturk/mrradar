import Foundation

public struct ProcessResult: Sendable {
    public var code: Int32
    public var stdout: Data
    public var stderr: String
    public var text: String { String(decoding: stdout, as: UTF8.self) }
}

public enum ProcessRunner {
    /// Runs a program to its end. Output is read while it runs, so a large answer can't fill the pipe.
    public static func run(_ path: String, _ arguments: [String], environment: [String: String], timeout: TimeInterval = 60) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let exited = AsyncStream<Void> { continuation in
            process.terminationHandler = { _ in continuation.yield(); continuation.finish() }
        }
        try process.run()
        let timer = Task {
            try? await Task.sleep(for: .seconds(timeout))
            if !Task.isCancelled, process.isRunning { process.terminate() }
        }
        async let stdout = Task.detached { out.fileHandleForReading.readDataToEndOfFile() }.value
        async let stderr = Task.detached { err.fileHandleForReading.readDataToEndOfFile() }.value
        let (outData, errData) = await (stdout, stderr)
        for await _ in exited { break }
        timer.cancel()
        return ProcessResult(code: process.terminationStatus, stdout: outData, stderr: String(decoding: errData, as: UTF8.self))
    }
}

/// The user's shell environment. An app opened from Finder starts with a bare PATH, so
/// tools are found through the login shell once and passed to every process it starts.
public actor ShellEnvironment {
    public static let shared = ShellEnvironment()
    private var cached: [String: String]?

    /// After an install the next lookup sees the new tool.
    public func invalidate() { cached = nil }

    public func environment() async -> [String: String] {
        if let cached { return cached }
        var env = ProcessInfo.processInfo.environment
        var path = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        if let shell = await Self.loginShellPath(env), !shell.isEmpty { path = shell }
        for folder in ["/opt/homebrew/bin", "/usr/local/bin", RadarPaths.tools.path]
        where !path.split(separator: ":").contains(Substring(folder)) {
            path += ":\(folder)"
        }
        env["PATH"] = path
        env["NO_COLOR"] = "1"
        cached = env
        return env
    }

    private static func loginShellPath(_ env: [String: String]) async -> String? {
        let shell = env["SHELL"] ?? "/bin/zsh"
        guard let result = try? await ProcessRunner.run(shell, ["-lic", "printf %s \"$PATH\""], environment: env, timeout: 8),
              result.code == 0 else { return nil }
        return result.text.split(separator: "\n").last.map(String.init)
    }

    public func which(_ tool: String) async -> String? {
        let env = await environment()
        return (env["PATH"] ?? "").split(separator: ":").map { "\($0)/\(tool)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

/// Where MRRadar keeps its files. `MRRADAR_HOME` moves them, for tests.
public enum RadarPaths {
    public static var home: URL {
        if let custom = ProcessInfo.processInfo.environment["MRRADAR_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MRRadar")
    }
    public static var tools: URL { home.appendingPathComponent("bin") }
    public static var cache: URL { home.appendingPathComponent("cache") }
    public static var alerts: URL { home.appendingPathComponent("alerts.json") }
    public static var preferences: URL { home.appendingPathComponent("preferences.json") }
    public static var control: URL { home.appendingPathComponent("control.json") }
}
