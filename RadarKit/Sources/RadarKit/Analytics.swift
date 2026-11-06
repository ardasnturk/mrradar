import Foundation

/// The numbers MRRadar adds on top of RevenueCat's. Pure functions, so tests can pin them down.
public enum Analytics {
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    public static func insights(
        overview: Overview, revenueDaily: [DatedValue], mrrDaily: [DatedValue], movement: [MovementWeek],
        churnWeekly: [DatedValue], trialsWeekly: [TrialWeek], countries: [Share], refundRate: Double?, now: Date
    ) -> Insights {
        let calendar = utc
        let arpu = overview.activeSubscriptions > 0 ? overview.mrr / overview.activeSubscriptions : nil

        var mrrChange: Double?
        var netNew: Double?
        if let latest = mrrDaily.last {
            let start = calendar.date(byAdding: .day, value: -30, to: latest.date)!
            if let then = mrrDaily.last(where: { $0.date <= start }) {
                netNew = latest.value - then.value
                if then.value > 0 { mrrChange = (latest.value - then.value) / then.value }
            }
        }

        let recent = movement.suffix(8)
        let gained = recent.reduce(0) { $0 + $1.gained }, lost = recent.reduce(0) { $0 + $1.lost }
        let quick: Double? = lost > 0 ? gained / lost : nil

        let churnWeeks = churnWeekly.suffix(8).map(\.value)
        var monthlyChurn: Double?
        if !churnWeeks.isEmpty {
            let weekly = churnWeeks.reduce(0, +) / Double(churnWeeks.count) / 100
            monthlyChurn = 1 - pow(1 - weekly, 52.0 / 12)
        }
        let lifetime = monthlyChurn.flatMap { $0 > 0 ? 1 / $0 : nil }
        let ltv: Double? = if let arpu, let lifetime { arpu * lifetime } else { nil }

        let today = calendar.dateComponents([.year, .month], from: now)
        let inMonth = revenueDaily.filter {
            let c = calendar.dateComponents([.year, .month], from: $0.date)
            return c.year == today.year && c.month == today.month
        }
        let monthToDate = inMonth.reduce(0) { $0 + $1.value }
        var pace: Double?
        let lastDays = revenueDaily.suffix(14)
        if !lastDays.isEmpty, let days = calendar.range(of: .day, in: .month, for: now)?.count {
            let daily = lastDays.reduce(0) { $0 + $1.value } / Double(lastDays.count)
            let left = max(0, days - inMonth.count)
            pace = monthToDate + daily * Double(left)
        }
        let previous = calendar.date(byAdding: .month, value: -1, to: now)!
        let previousParts = calendar.dateComponents([.year, .month], from: previous)
        let lastMonthDays = revenueDaily.filter {
            let c = calendar.dateComponents([.year, .month], from: $0.date)
            return c.year == previousParts.year && c.month == previousParts.month
        }
        let lastMonth = lastMonthDays.isEmpty ? nil : lastMonthDays.reduce(0) { $0 + $1.value }

        let trials = trialsWeekly.suffix(8)
        let converted = trials.reduce(0) { $0 + $1.conversions }
        let ended = trials.reduce(0) { $0 + $1.completed }
        let conversion: Double? = ended > 0 ? converted / ended : nil
        let pipeline: Double? = if let conversion, let arpu { overview.activeTrials * conversion * arpu } else { nil }

        let weekday = weekdayIndex(revenueDaily.suffix(84))
        let line = trend(mrrDaily.suffix(60), days: 90)

        return Insights(
            arr: overview.mrr * 12, mrrChange30: mrrChange, netNewMRR30: netNew, quickRatio: quick, arpu: arpu,
            monthlyChurn: monthlyChurn, lifetimeMonths: lifetime, impliedLTV: ltv, monthToDate: monthToDate,
            monthEndPace: pace, lastMonth: lastMonth, trialConversion: conversion, trialPipelineMRR: pipeline,
            weekdayIndex: weekday, bestWeekday: weekday.isEmpty ? nil : weekday.indices.max { weekday[$0] < weekday[$1] },
            topCountryShare: countries.first?.fraction, refundRate: refundRate, forecast: line.points, forecastFit: line.fit
        )
    }

    /// Average revenue of each weekday against the average day, Monday first. Empty without data.
    public static func weekdayIndex<S: Sequence>(_ days: S) -> [Double] where S.Element == DatedValue {
        var sums = [Double](repeating: 0, count: 7), counts = [Double](repeating: 0, count: 7)
        let calendar = utc
        for day in days {
            let index = (calendar.component(.weekday, from: day.date) + 5) % 7
            sums[index] += day.value
            counts[index] += 1
        }
        guard counts.allSatisfy({ $0 > 0 }) else { return [] }
        let averages = zip(sums, counts).map { $0 / $1 }
        let mean = averages.reduce(0, +) / 7
        return mean > 0 ? averages.map { $0 / mean } : []
    }

    /// Least-squares line through `values`, extended `days` past the last point.
    public static func trend<S: Sequence>(_ values: S, days: Int) -> (points: [DatedValue], fit: Double?) where S.Element == DatedValue {
        let values = Array(values)
        guard values.count >= 14, let last = values.last else { return ([], nil) }
        let xs = values.map { $0.date.timeIntervalSince(last.date) / 86400 }, ys = values.map(\.value)
        let n = Double(values.count)
        let meanX = xs.reduce(0, +) / n, meanY = ys.reduce(0, +) / n
        let sxx = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        let sxy = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let syy = ys.reduce(0) { $0 + ($1 - meanY) * ($1 - meanY) }
        guard sxx > 0 else { return ([], nil) }
        let slope = sxy / sxx, intercept = meanY - slope * meanX
        let fit: Double = syy > 0 ? (sxy * sxy) / (sxx * syy) : 1
        let points = stride(from: 0, through: days, by: 7).map { offset in
            DatedValue(
                date: last.date.addingTimeInterval(Double(offset) * 86400),
                value: max(0, intercept + slope * Double(offset))
            )
        }
        return (points, fit)
    }

    /// Days far from the 28 before them, by median absolute deviation, which one big day doesn't skew.
    public static func anomalies(_ days: [DatedValue], threshold: Double = 3.5) -> [Anomaly] {
        guard days.count > 28 else { return [] }
        var found: [Anomaly] = []
        for index in 28..<days.count {
            let window = days[(index - 28)..<index].map(\.value).sorted()
            let median = window[window.count / 2]
            let deviations = window.map { abs($0 - median) }.sorted()
            let mad = deviations[deviations.count / 2]
            guard mad > 0 else { continue }
            let score = 0.6745 * (days[index].value - median) / mad
            if abs(score) >= threshold { found.append(Anomaly(date: days[index].date, value: days[index].value, expected: median)) }
        }
        return found
    }

    public static func portfolio(_ reports: [ProjectReport]) -> Portfolio {
        let groups = Dictionary(grouping: reports, by: \.overview.currency)
        let totals = groups.keys.sorted().map { currency -> PortfolioTotal in
            let members = groups[currency]!
            let mrr = members.reduce(0) { $0 + $1.overview.mrr }
            var byDay: [Date: Double] = [:]
            for report in members {
                for day in report.revenueDaily { byDay[day.date, default: 0] += day.value }
            }
            let then = members.reduce(0.0) { sum, report in
                guard let change = report.insights.mrrChange30 else { return sum + report.overview.mrr }
                return sum + report.overview.mrr / (1 + change)
            }
            return PortfolioTotal(
                currency: currency, mrr: mrr,
                revenue28: members.reduce(0) { $0 + $1.overview.revenue28 },
                activeSubscriptions: members.reduce(0) { $0 + $1.overview.activeSubscriptions },
                activeTrials: members.reduce(0) { $0 + $1.overview.activeTrials },
                mrrChange30: then > 0 ? (mrr - then) / then : nil,
                revenueDaily: byDay.keys.sorted().map { DatedValue(date: $0, value: byDay[$0]!) },
                mrrShare: members.filter { $0.overview.mrr > 0 }.sorted { $0.overview.mrr > $1.overview.mrr }
                    .map { Share(name: $0.project.name, value: $0.overview.mrr, fraction: mrr > 0 ? $0.overview.mrr / mrr : 0) }
            )
        }
        return Portfolio(totals: totals, reports: reports.sorted { $0.overview.mrr > $1.overview.mrr }, updatedAt: reports.map(\.updatedAt).max())
    }
}
