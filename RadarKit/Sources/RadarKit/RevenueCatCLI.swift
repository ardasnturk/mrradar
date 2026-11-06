import Foundation

public enum RadarError: LocalizedError, Sendable, Equatable {
    case cliMissing
    case signedOut
    case rateLimited
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .cliMissing: "The RevenueCat CLI is not installed."
        case .signedOut: "Sign in to RevenueCat again."
        case .rateLimited: "RevenueCat asked to slow down."
        case .failed(let message): message
        }
    }
}

public struct RCProject: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var iconURL: String?

    public init(id: String, name: String, iconURL: String? = nil) {
        self.id = id
        self.name = name
        self.iconURL = iconURL
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case iconURL = "icon_url"
    }
}

/// What the engine needs from RevenueCat. `RevenueCatCLI` asks `rc`, `DemoSource` makes it up.
public protocol RevenueCatSource: Sendable {
    func projects() async throws -> [RCProject]
    /// A GET on REST API v2, e.g. `/projects/x/charts/mrr?resolution=1`.
    func get(_ path: String) async throws -> Data
}

/// Talks to RevenueCat only through the official `rc` CLI, which holds the sign-in. MRRadar never
/// sees the OAuth token. An API key pasted in onboarding lives in the Keychain and reaches
/// `rc` through its environment, never its arguments.
public struct RevenueCatCLI: RevenueCatSource {
    public init() {}

    func executable() async throws -> String {
        guard let path = await ShellEnvironment.shared.which("rc") else { throw RadarError.cliMissing }
        return path
    }

    private func environment() async -> [String: String] {
        var env = await ShellEnvironment.shared.environment()
        if let key = KeychainKey.read() { env["RC_API_KEY"] = key }
        return env
    }

    func run(_ arguments: [String], timeout: TimeInterval = 60) async throws -> Data {
        let result = try await ProcessRunner.run(try await executable(), arguments + ["--no-input"], environment: await environment(), timeout: timeout)
        guard result.code == 0 else { throw Self.error(from: result) }
        return result.stdout
    }

    static func error(from result: ProcessResult) -> RadarError {
        let text = (result.text + "\n" + result.stderr).lowercased()
        if text.contains("429") || text.contains("rate limit") { return .rateLimited }
        if text.contains("not logged in") || text.contains("unauthorized") || text.contains("401") || text.contains("rc auth login") { return .signedOut }
        struct Envelope: Decodable {
            struct Failure: Decodable { var message: String }
            var error: Failure
        }
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: result.stdout) { return .failed(envelope.error.message) }
        let line = result.stderr.split(separator: "\n").first.map(String.init)
        return .failed(line ?? "rc exited with \(result.code)")
    }

    public func projects() async throws -> [RCProject] {
        struct Page: Decodable {
            struct Items: Decodable { var items: [RCProject] }
            var data: Items
        }
        return try JSONDecoder().decode(Page.self, from: try await run(["projects", "list", "--json"])).data.items
    }

    public func get(_ path: String) async throws -> Data {
        try await run(["api", "GET", path])
    }

    public func version() async -> String? {
        guard let data = try? await run(["--version"], timeout: 10) else { return nil }
        return String(decoding: data, as: UTF8.self).split(separator: " ").last.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// True when `rc` can reach the account. Asks the API, so an expired login counts as signed out.
    public func isSignedIn() async -> Bool {
        (try? await projects()) != nil
    }

    /// Opens the browser and waits until the user has approved, or five minutes pass.
    public func signIn() async throws {
        _ = try await ProcessRunner.run(try await executable(), ["auth", "login", "--oauth"], environment: await environment(), timeout: 300)
        guard await isSignedIn() else { throw RadarError.signedOut }
    }

    public func signOut() async throws {
        KeychainKey.delete()
        _ = try? await ProcessRunner.run(try await executable(), ["auth", "logout", "--no-input"], environment: await environment(), timeout: 30)
    }

    /// Whether this sign-in may read charts for the project. A secret key can lack that permission.
    public func canReadCharts(_ project: String) async -> Bool {
        (try? await get("/projects/\(project)/metrics/overview")) != nil
    }
}
