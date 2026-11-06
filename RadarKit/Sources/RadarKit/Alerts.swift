import Foundation

public struct RadarAlert: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case newSubscribers, mrrDrop, mrrMilestone, revenueSpike, revenueDip, refundSpike, churnSpike
    }

    public var id: String
    public var kind: Kind
    public var projectID: String
    public var projectName: String
    public var date: Date
    /// The amount or count the alert is about.
    public var value: Double
    /// A share, 0.1 = 10 %, for the kinds that have one.
    public var fraction: Double?
    public var currency: String?
}

/// Which alerts are on, and how far a number must move to raise one.
public struct AlertRules: Codable, Sendable, Hashable {
    public var enabled: [RadarAlert.Kind: Bool]
    /// MRR lost within 7 days, 0.05 = 5 %.
    public var mrrDrop: Double
    /// Refund share of last month's transactions.
    public var refundRate: Double
    /// Rise of weekly churn against the 8 weeks before, 0.5 = half as high again.
    public var churnRise: Double

    public static let standard = AlertRules(
        enabled: Dictionary(uniqueKeysWithValues: RadarAlert.Kind.allCases.map { ($0, true) }),
        mrrDrop: 0.05, refundRate: 0.05, churnRise: 0.5
    )

    public func isOn(_ kind: RadarAlert.Kind) -> Bool { enabled[kind] ?? true }
}

/// Turns two snapshots of a project into alerts. An alert's id holds its day, so it fires once.
public enum AlertRulesEngine {
    static let milestones: [Double] = [100, 250, 500, 1000, 2500, 5000, 10000, 25000, 50000, 100000, 250000, 500000, 1000000]
    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    public static func alerts(previous: ProjectReport?, current: ProjectReport, rules: AlertRules, now: Date) -> [RadarAlert] {
        var found: [RadarAlert] = []
        let stamp = day.string(from: now)
        let project = current.project, currency = current.overview.currency
        func add(_ kind: RadarAlert.Kind, _ key: String, value: Double, fraction: Double? = nil, date: Date = now, money: Bool = true) {
            guard rules.isOn(kind) else { return }
            found.append(RadarAlert(
                id: "\(project.id).\(kind.rawValue).\(key)", kind: kind, projectID: project.id, projectName: project.name,
                date: date, value: value, fraction: fraction, currency: money ? currency : nil
            ))
        }

        if let previous {
            let gained = current.overview.activeSubscriptions - previous.overview.activeSubscriptions
            if gained >= 1 {
                add(.newSubscribers, "\(stamp).\(Int(current.overview.activeSubscriptions))", value: gained, money: false)
            }
            if let milestone = milestones.last(where: { previous.overview.mrr < $0 && current.overview.mrr >= $0 }) {
                add(.mrrMilestone, "\(Int(milestone))", value: milestone)
            }
        }

        let mrr = current.mrrDaily
        if let latest = mrr.last, mrr.count > 7, mrr[mrr.count - 8].value > 0 {
            let then = mrr[mrr.count - 8].value
            let change = (latest.value - then) / then
            if change <= -rules.mrrDrop { add(.mrrDrop, stamp, value: then - latest.value, fraction: -change) }
        }

        if let last = current.revenueDaily.dropLast().last, let anomaly = current.anomalies.last, anomaly.date == last.date {
            let up = anomaly.value > anomaly.expected
            let change = anomaly.expected > 0 ? abs(anomaly.value - anomaly.expected) / anomaly.expected : nil
            add(up ? .revenueSpike : .revenueDip, day.string(from: anomaly.date), value: anomaly.value, fraction: change, date: anomaly.date)
        }

        if let refund = current.insights.refundRate, refund >= rules.refundRate {
            add(.refundSpike, String(stamp.prefix(7)), value: refund, fraction: refund, money: false)
        }

        let weeks = current.churnWeekly.map(\.value)
        if weeks.count >= 9, let last = weeks.last {
            let base = weeks.dropLast().suffix(8).reduce(0, +) / 8
            if base > 0, last >= base * (1 + rules.churnRise) {
                add(.churnSpike, stamp, value: last / 100, fraction: (last - base) / base, money: false)
            }
        }
        return found
    }
}
