import Foundation

/// Made-up apps for screenshots and for trying MRRadar without an account (`--demo`).
/// Answers the same paths as the API, so all of MRRadar's calculations run on it.
public struct DemoSource: RevenueCatSource {
    public init() {}

    private static let apps: [(project: RCProject, mrr: Double, growth: Double, subs: Double, trials: Double)] = [
        (RCProject(id: "demo_pulse", name: "Pulse Habit"), 4_820, 0.0016, 612, 48),
        (RCProject(id: "demo_lumen", name: "Lumen Notes"), 2_150, 0.0009, 301, 22),
        (RCProject(id: "demo_orbit", name: "Orbit Weather"), 860, -0.0012, 148, 9),
        (RCProject(id: "demo_mint", name: "Mint Budget"), 390, 0.0031, 71, 14),
    ]

    public func projects() async throws -> [RCProject] { Self.apps.map(\.project) }

    public func get(_ path: String) async throws -> Data {
        let parts = path.split(separator: "?", maxSplits: 1)
        let segments = parts[0].split(separator: "/").map(String.init)
        guard segments.count >= 4, let app = Self.apps.first(where: { $0.project.id == segments[1] }) else {
            throw RadarError.failed("Unknown demo path")
        }
        var query: [String: String] = [:]
        for pair in parts.dropFirst().first?.split(separator: "&") ?? [] {
            let item = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if item.count == 2 { query[item[0]] = item[1] }
        }
        let object: [String: Any]
        if segments[2] == "metrics" {
            object = [
                "currency": "USD",
                "metrics": [
                    ["id": "mrr", "value": app.mrr], ["id": "revenue", "value": app.mrr * 1.08],
                    ["id": "active_subscriptions", "value": app.subs], ["id": "active_trials", "value": app.trials],
                    ["id": "new_customers", "value": app.subs * 2.4], ["id": "active_users", "value": app.subs * 9],
                ],
            ]
        } else {
            object = chart(segments[3], app: app, query: query)
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func chart(_ name: String, app: (project: RCProject, mrr: Double, growth: Double, subs: Double, trials: Double), query: [String: String]) -> [String: Any] {
        let step: TimeInterval = query["resolution"] == "0" ? 86400 : (query["resolution"] == "1" ? 7 * 86400 : 30 * 86400)
        let days = (name == "revenue" && query["resolution"] == "0") ? 400 : (query["resolution"] == "0" ? 120 : 182)
        let count = Int(Double(days) * 86400 / step)
        let end = Calendar(identifier: .gregorian).startOfDay(for: .now).timeIntervalSince1970
        let dates = (0..<count).map { end - Double(count - 1 - $0) * step }
        // A repeatable wobble, so the charts don't change on every refresh.
        func wobble(_ i: Int, _ salt: Double = 1) -> Double {
            let x = sin(Double(i) * 12.9898 * salt + app.mrr) * 43758.5453
            return x - floor(x)
        }
        func values(_ build: (Int) -> Double, measure: Int = 0) -> [[String: Any]] {
            dates.indices.map { ["cohort": dates[$0], "value": build($0), "measure": measure, "incomplete": false] }
        }
        func measures(_ names: String...) -> [[String: Any]] { names.map { ["display_name": $0] } }
        switch name {
        case "revenue":
            if let segment = query["segment"] {
                let names = segment == "store" ? ["App Store", "Play Store"] : ["United States", "Germany", "Turkey", "United Kingdom", "Japan"]
                var points: [[String: Any]] = []
                for (index, _) in names.enumerated() {
                    points.append(["cohort": end, "value": app.mrr / Double(index + 1), "measure": 0, "segment": index + 1, "incomplete": false])
                }
                return ["measures": measures("Revenue"), "values": points, "segments": [["display_name": "Total", "is_total": true]] + names.map { ["display_name": $0, "is_total": false] }]
            }
            let average = app.mrr * 1.08 / 28
            return ["measures": measures("Revenue"), "values": values { i in
                let weekday = Calendar(identifier: .gregorian).component(.weekday, from: Date(timeIntervalSince1970: dates[i]))
                let weekend = weekday == 1 || weekday == 7 ? 1.28 : 0.9
                return average * weekend * (0.72 + wobble(i) * 0.56) * pow(1 + app.growth, Double(i - count))
            }]
        case "mrr":
            return ["measures": measures("MRR"), "values": values { i in
                app.mrr * pow(1 + app.growth, Double(i - count + 1)) * (0.995 + wobble(i) * 0.01)
            }]
        case "mrr_movement":
            let gain = app.mrr * 0.05
            return ["measures": measures("New MRR", "Resubscription MRR", "Expansion MRR", "Churned MRR", "Contraction MRR"),
                    "values": values({ gain * (0.7 + wobble($0) * 0.6) }, measure: 0)
                        + values({ gain * 0.12 * wobble($0, 2) }, measure: 1)
                        + values({ gain * 0.05 * wobble($0, 3) }, measure: 2)
                        + values({ gain * (0.55 + wobble($0, 4) * 0.5 - app.growth * 60) }, measure: 3)
                        + values({ gain * 0.04 * wobble($0, 5) }, measure: 4)]
        case "churn":
            return ["measures": measures("Actives", "Churned Actives", "Churn Rate"),
                    "values": values({ 0.9 + wobble($0) * 0.9 }, measure: 2)]
        case "trial_conversion_rate":
            let starts = app.trials * 1.4
            return ["measures": measures("Trial Starts", "Conversions", "Completed Trials", "Conversion Rate"),
                    "values": values({ starts * (0.8 + wobble($0) * 0.4) }, measure: 0)
                        + values({ starts * (0.8 + wobble($0) * 0.4) * (0.32 + wobble($0, 2) * 0.1) }, measure: 1)
                        + values({ starts * (0.8 + wobble($0) * 0.4) }, measure: 2)]
        case "refund_rate":
            return ["measures": measures("Transactions", "Refunded Transactions", "Refund Rate"),
                    "values": values({ 1.1 + wobble($0) }, measure: 2)]
        case "subscription_retention":
            var periods: [[String: Any]] = [["display_name": "Subscriptions"]]
            for month in 1...6 {
                periods.append(["display_name": "Month \(month)", "scale": "absolute"])
                periods.append(["display_name": "Month \(month) rate", "scale": "relative"])
            }
            var points: [[String: Any]] = []
            for row in 0..<7 {
                let date = end - Double(6 - row) * 30 * 86400
                points.append(["cohort": date, "period": 0, "value": 120 + wobble(row) * 80])
                for month in 1...max(1, 6 - row) where row < 6 {
                    let rate = 100 * pow(0.72 + wobble(row, 2) * 0.06, Double(month))
                    points.append(["cohort": date, "period": month * 2, "value": rate])
                }
            }
            return ["periods": periods, "values": points]
        default:
            return ["measures": measures("Value"), "values": values { _ in 0 }]
        }
    }
}
