import Foundation

/// Settings the app and the hub share, in `preferences.json`.
public struct RadarPreferences: Codable, Sendable, Hashable {
    public var setupFinished = false
    /// Projects to follow; nil means all of them.
    public var trackedProjects: [String]?
    public var overviewMinutes = 15
    public var chartHours = 6
    public var alerts = AlertRules.standard
    public var notifyOnMac = true

    public init() {}

    public static func load() -> RadarPreferences {
        guard let data = try? Data(contentsOf: RadarPaths.preferences),
              let preferences = try? JSONDecoder().decode(RadarPreferences.self, from: data) else { return RadarPreferences() }
        return preferences
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: RadarPaths.home, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: RadarPaths.preferences, options: .atomic)
    }
}
