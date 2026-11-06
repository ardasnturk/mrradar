import Foundation

public struct DatedValue: Codable, Sendable, Hashable, Identifiable {
    public var date: Date
    public var value: Double
    public var id: Date { date }
    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

public struct Share: Codable, Sendable, Hashable, Identifiable {
    public var name: String
    public var value: Double
    public var fraction: Double
    public var id: String { name }
}

public struct RetentionRow: Codable, Sendable, Hashable, Identifiable {
    public var cohort: Date
    public var size: Double
    public var cells: [Double?]
    public var id: Date { cohort }
}

public struct MovementWeek: Codable, Sendable, Hashable, Identifiable {
    public var date: Date
    public var gained: Double
    public var lost: Double
    public var net: Double { gained - lost }
    public var id: Date { date }
}

public struct TrialWeek: Codable, Sendable, Hashable, Identifiable {
    public var date: Date
    public var starts: Double
    public var conversions: Double
    /// Trials that have ended, converted or not.
    public var completed: Double
    /// 0…1, of the trials that have ended.
    public var rate: Double? { completed > 0 ? conversions / completed : nil }
    public var id: Date { date }
}

public struct Overview: Codable, Sendable, Hashable {
    public var currency: String
    public var mrr: Double
    public var revenue28: Double
    public var activeSubscriptions: Double
    public var activeTrials: Double
    public var newCustomers28: Double
    public var activeUsers28: Double

    public init(currency: String, mrr: Double, revenue28: Double, activeSubscriptions: Double, activeTrials: Double, newCustomers28: Double, activeUsers28: Double) {
        self.currency = currency
        self.mrr = mrr
        self.revenue28 = revenue28
        self.activeSubscriptions = activeSubscriptions
        self.activeTrials = activeTrials
        self.newCustomers28 = newCustomers28
        self.activeUsers28 = activeUsers28
    }
}

/// What MRRadar works out, none of which RevenueCat shows as one number.
public struct Insights: Codable, Sendable, Hashable {
    public var arr: Double
    /// Change over the last 30 days, 0.1 = +10 %.
    public var mrrChange30: Double?
    public var netNewMRR30: Double?
    /// MRR won per unit lost over the last 8 weeks. Above 4 is strong, below 1 is shrinking.
    public var quickRatio: Double?
    /// MRR per active subscription.
    public var arpu: Double?
    /// Monthly share of subscribers lost, 0…1.
    public var monthlyChurn: Double?
    public var lifetimeMonths: Double?
    /// `arpu / monthlyChurn`.
    public var impliedLTV: Double?
    public var monthToDate: Double
    /// Where this calendar month ends at the pace of the last 14 days.
    public var monthEndPace: Double?
    public var lastMonth: Double?
    /// Of the trials that have ended in the last 8 weeks, 0…1.
    public var trialConversion: Double?
    /// MRR the running trials should add at that conversion.
    public var trialPipelineMRR: Double?
    /// Monday first. 1 = an average day.
    public var weekdayIndex: [Double]
    public var bestWeekday: Int?
    public var topCountryShare: Double?
    public var refundRate: Double?
    /// Trend of the last 60 days of MRR, a straight line for the next 90.
    public var forecast: [DatedValue]
    /// 0…1. How well that line fits.
    public var forecastFit: Double?
}

public struct ProjectReport: Codable, Sendable, Hashable, Identifiable {
    public var project: RCProject
    public var overview: Overview
    public var updatedAt: Date
    /// When the charts behind everything below were last read; nil until they have been.
    public var chartsUpdatedAt: Date?
    public var revenueDaily: [DatedValue]
    public var mrrDaily: [DatedValue]
    public var movement: [MovementWeek]
    public var churnWeekly: [DatedValue]
    public var trialsWeekly: [TrialWeek]
    public var retention: [RetentionRow]
    public var countries: [Share]
    public var stores: [Share]
    public var anomalies: [Anomaly]
    public var insights: Insights
    public var id: String { project.id }

    public init(project: RCProject, overview: Overview, updatedAt: Date) {
        self.project = project
        self.overview = overview
        self.updatedAt = updatedAt
        revenueDaily = []
        mrrDaily = []
        movement = []
        churnWeekly = []
        trialsWeekly = []
        retention = []
        countries = []
        stores = []
        anomalies = []
        insights = Analytics.insights(overview: overview, revenueDaily: [], mrrDaily: [], movement: [], churnWeekly: [], trialsWeekly: [], countries: [], refundRate: nil, now: updatedAt)
    }
}

public struct Anomaly: Codable, Sendable, Hashable, Identifiable {
    public var date: Date
    public var value: Double
    public var expected: Double
    public var id: Date { date }
}

/// All projects that share a currency. Amounts in different currencies are never added.
public struct PortfolioTotal: Codable, Sendable, Hashable, Identifiable {
    public var currency: String
    public var mrr: Double
    public var revenue28: Double
    public var activeSubscriptions: Double
    public var activeTrials: Double
    public var mrrChange30: Double?
    public var revenueDaily: [DatedValue]
    public var mrrShare: [Share]
    public var id: String { currency }
}

public struct Portfolio: Codable, Sendable, Hashable {
    public var totals: [PortfolioTotal]
    public var reports: [ProjectReport]
    public var updatedAt: Date?

    public static let empty = Portfolio(totals: [], reports: [], updatedAt: nil)

    public init(totals: [PortfolioTotal], reports: [ProjectReport], updatedAt: Date?) {
        self.totals = totals
        self.reports = reports
        self.updatedAt = updatedAt
    }
}
