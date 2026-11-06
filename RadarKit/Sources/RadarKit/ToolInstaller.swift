import CryptoKit
import Foundation

/// Puts `rc` on a Mac that doesn't have it: Homebrew when it is there, otherwise the official
/// GitHub release, checked against the release's `checksums.txt`, into MRRadar's own folder.
public enum ToolInstaller {
    struct Release: Decodable {
        struct Asset: Decodable {
            var name: String
            var url: URL
            enum CodingKeys: String, CodingKey {
                case name
                case url = "browser_download_url"
            }
        }
        var tagName: String
        var assets: [Asset]
        enum CodingKeys: String, CodingKey {
            case assets
            case tagName = "tag_name"
        }
    }

    public static func installRevenueCatCLI(progress: @Sendable (String) -> Void) async throws {
        if let brew = await ShellEnvironment.shared.which("brew") {
            progress("Installing with Homebrew…")
            let env = await ShellEnvironment.shared.environment()
            let result = try await ProcessRunner.run(brew, ["install", "RevenueCat/tap/rc"], environment: env, timeout: 600)
            await ShellEnvironment.shared.invalidate()
            if result.code == 0, await ShellEnvironment.shared.which("rc") != nil { return }
        }
        progress("Downloading the official release…")
        try await installFromRelease()
        await ShellEnvironment.shared.invalidate()
        guard await ShellEnvironment.shared.which("rc") != nil else {
            throw RadarError.failed("The CLI was installed but can't be started.")
        }
    }

    static var architecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "amd64"
        #endif
    }

    private static func installFromRelease() async throws {
        let api = URL(string: "https://api.github.com/repos/RevenueCat/cli/releases/latest")!
        let (data, _) = try await URLSession.shared.data(from: api)
        let release = try JSONDecoder().decode(Release.self, from: data)
        let version = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
        let name = "rc_\(version)_darwin_\(architecture).tar.gz"
        guard let archive = release.assets.first(where: { $0.name == name }),
              let checksums = release.assets.first(where: { $0.name == "checksums.txt" }) else {
            throw RadarError.failed("The release has no build for this Mac.")
        }
        let (sumData, _) = try await URLSession.shared.data(from: checksums.url)
        let (file, _) = try await URLSession.shared.download(from: archive.url)
        defer { try? FileManager.default.removeItem(at: file) }
        let actual = SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
        guard expectedChecksum(in: String(decoding: sumData, as: UTF8.self), for: name) == actual else {
            throw RadarError.failed("The download doesn't match the release's checksum, so it wasn't installed.")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let env = await ShellEnvironment.shared.environment()
        let result = try await ProcessRunner.run("/usr/bin/tar", ["-xzf", file.path, "-C", folder.path], environment: env)
        guard result.code == 0 else { throw RadarError.failed("The download could not be unpacked.") }
        try FileManager.default.createDirectory(at: RadarPaths.tools, withIntermediateDirectories: true)
        let target = RadarPaths.tools.appendingPathComponent("rc")
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: folder.appendingPathComponent("rc"), to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
    }

    static func expectedChecksum(in text: String, for name: String) -> String? {
        for line in text.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace)
            if parts.count == 2, parts[1].hasSuffix(name) { return String(parts[0]).lowercased() }
        }
        return nil
    }
}
