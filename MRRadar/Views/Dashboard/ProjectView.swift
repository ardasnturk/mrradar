import Charts
import RadarKit
import SwiftUI

struct ProjectView: View {
    @Environment(AppModel.self) private var model
    let id: String
    @State private var range = 90

    private var report: ProjectReport? {
        model.selectedReport?.id == id ? model.selectedReport : nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ErrorBanner()
                if let report {
                    content(report)
                } else {
                    ProgressView().padding(.top, 120)
                }
            }
            .padding(20)
        }
        .navigationTitle(Text(verbatim: report?.project.name ?? "MRRadar"))
        .task { await model.select(project: id) }
    }

    @ViewBuilder private func content(_ report: ProjectReport) -> some View {
        let insights = report.insights, currency = report.overview.currency
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
            KPICard(title: "MRR", value: Format.money(report.overview.mrr, currency), detail: insights.mrrChange30.map(Format.signedPercent), positive: insights.mrrChange30.map { $0 >= 0 })
            KPICard(title: "ARR", value: Format.money(insights.arr, currency))
            KPICard(title: "Subscribers", value: Format.count(report.overview.activeSubscriptions), detail: insights.arpu.map { String(localized: "\(Format.money($0, currency)) each") })
            KPICard(title: "Active trials", value: Format.count(report.overview.activeTrials), detail: insights.trialConversion.map { String(localized: "\(Format.percent($0)) convert") })
            KPICard(title: "Quick ratio", value: insights.quickRatio.map(Format.ratio) ?? "—", positive: nil, help: "MRR won per unit lost over the last 8 weeks.")
            KPICard(title: "Implied LTV", value: insights.impliedLTV.map { Format.money($0, currency) } ?? "—", detail: insights.lifetimeMonths.map { String(localized: "\(Format.months($0)) months") }, help: "MRR per subscriber divided by monthly churn.")
        }
        if report.chartsUpdatedAt == nil {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading charts. RevenueCat limits this, so it takes about half a minute per app.").font(.callout).foregroundStyle(.secondary)
            }
            .glassCard(padding: 10)
        } else {
            takeaways(report)
            HStack(alignment: .top, spacing: 12) {
                forecast(report)
                movement(report)
            }
            revenue(report)
            HStack(alignment: .top, spacing: 12) {
                weekdays(report)
                trials(report)
                churn(report)
            }
            if !report.retention.isEmpty { retention(report) }
            HStack(alignment: .top, spacing: 12) {
                shares("Countries", report.countries)
                shares("Stores", report.stores)
            }
        }
    }

    /// Plain sentences, from the numbers below.
    @ViewBuilder private func takeaways(_ report: ProjectReport) -> some View {
        let lines = Self.takeaways(report)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(lines, id: \.self) { line in
                    Label(line, systemImage: "sparkle").font(.callout)
                }
            }
            .glassCard()
        }
    }

    static func takeaways(_ report: ProjectReport) -> [String] {
        let insights = report.insights, currency = report.overview.currency
        var lines: [String] = []
        if let pace = insights.monthEndPace, let last = insights.lastMonth, last > 0 {
            let amount = Format.money(pace, currency)
            let change = Format.signedPercent((pace - last) / last)
            lines.append(String(localized: "At this pace the month ends at \(amount), \(change) against last month."))
        }
        if let pipeline = insights.trialPipelineMRR, pipeline > 0 {
            lines.append(String(localized: "Running trials should add about \(Format.money(pipeline, currency)) of MRR."))
        }
        if let day = insights.bestWeekday, insights.weekdayIndex.count == 7 {
            let name = Calendar.current.standaloneWeekdaySymbols[(day + 1) % 7]
            lines.append(String(localized: "\(name) is your best day, \(Format.signedPercent(insights.weekdayIndex[day] - 1)) against an average day."))
        }
        if let share = insights.topCountryShare, share > 0.5, let country = report.countries.first?.name {
            lines.append(String(localized: "\(Format.percent(share, digits: 0)) of revenue comes from \(country)."))
        }
        return lines
    }

    private func forecast(_ report: ProjectReport) -> some View {
        ChartCard(title: "MRR and where it's heading", subtitle: "Dashed: a straight line through the last 60 days, for 90 more. A trend, not a promise.") {
            Chart {
                ForEach(report.mrrDaily) { day in
                    LineMark(x: .value("Date", day.date), y: .value("MRR", day.value), series: .value("Series", "MRR"))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Brand.emerald)
                }
                ForEach(report.insights.forecast) { day in
                    LineMark(x: .value("Date", day.date), y: .value("MRR", day.value), series: .value("Series", "Forecast"))
                        .foregroundStyle(Brand.gold)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 220)
        }
    }

    private func movement(_ report: ProjectReport) -> some View {
        ChartCard(title: "MRR won and lost", subtitle: "Each week: new, returning and upgraded subscribers against those who left.") {
            Chart(report.movement) { week in
                BarMark(x: .value("Week", week.date, unit: .weekOfYear), y: .value("Won", week.gained)).foregroundStyle(Brand.emerald)
                BarMark(x: .value("Week", week.date, unit: .weekOfYear), y: .value("Lost", -week.lost)).foregroundStyle(Brand.coral)
            }
            .frame(height: 220)
        }
    }

    private func revenue(_ report: ProjectReport) -> some View {
        let days = Array(report.revenueDaily.suffix(range))
        let first = days.first?.date ?? .distantPast
        return ChartCard(title: "Daily revenue", subtitle: "Marked days are far from the 28 before them.") {
            Picker("Period", selection: $range) {
                Text("30 days").tag(30)
                Text("90 days").tag(90)
                Text("1 year").tag(365)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 280)
            Chart {
                ForEach(days) { day in
                    BarMark(x: .value("Date", day.date, unit: .day), y: .value("Revenue", day.value))
                        .foregroundStyle(Brand.teal.opacity(0.8))
                }
                ForEach(report.anomalies.filter { $0.date >= first }) { anomaly in
                    PointMark(x: .value("Date", anomaly.date, unit: .day), y: .value("Revenue", anomaly.value))
                        .foregroundStyle(anomaly.value > anomaly.expected ? Brand.gold : Brand.coral)
                }
            }
            .frame(height: 220)
        }
    }

    private func weekdays(_ report: ProjectReport) -> some View {
        let names = Calendar.current.veryShortStandaloneWeekdaySymbols
        let rows = report.insights.weekdayIndex.enumerated().map { (offset: $0.offset, name: names[($0.offset + 1) % 7], value: $0.element) }
        return ChartCard(title: "Best days", subtitle: "Against an average day, last 12 weeks.") {
            Chart(rows, id: \.offset) { row in
                BarMark(x: .value("Day", "\(row.offset) \(row.name)"), y: .value("Index", row.value))
                    .foregroundStyle(row.value >= 1 ? Brand.emerald : Brand.teal.opacity(0.5))
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel { Text(verbatim: value.as(String.self)?.split(separator: " ").last.map(String.init) ?? "") }
                }
            }
            .frame(height: 170)
        }
    }

    private func trials(_ report: ProjectReport) -> some View {
        ChartCard(title: "Trials", subtitle: "Started, and converted, each week.") {
            Chart(report.trialsWeekly) { week in
                BarMark(x: .value("Week", week.date, unit: .weekOfYear), y: .value("Started", week.starts), stacking: .unstacked).foregroundStyle(Brand.teal.opacity(0.35))
                BarMark(x: .value("Week", week.date, unit: .weekOfYear), y: .value("Converted", week.conversions), stacking: .unstacked).foregroundStyle(Brand.emerald)
            }
            .frame(height: 170)
        }
    }

    private func churn(_ report: ProjectReport) -> some View {
        ChartCard(title: "Weekly churn", subtitle: "Share of subscribers lost.") {
            Chart(report.churnWeekly) { week in
                LineMark(x: .value("Week", week.date), y: .value("Churn", week.value / 100))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Brand.coral)
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel { Text(verbatim: value.as(Double.self).map { Format.percent($0) } ?? "") }
                }
            }
            .frame(height: 170)
        }
    }

    private func retention(_ report: ProjectReport) -> some View {
        let columns = report.retention.map(\.cells.count).max() ?? 0
        return ChartCard(title: "Retention by month", subtitle: "Share of each month's new subscribers still paying.") {
            Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                ForEach(report.retention) { row in
                    GridRow {
                        Text(row.cohort, format: .dateTime.month(.abbreviated).year(.twoDigits))
                            .font(.caption).foregroundStyle(.secondary).gridColumnAlignment(.leading)
                        Text(verbatim: Format.count(row.size)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        ForEach(0..<columns, id: \.self) { column in
                            cell(column < row.cells.count ? row.cells[column] : nil)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func cell(_ value: Double?) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(value.map { Brand.emerald.opacity(0.12 + $0 * 0.8) } ?? Color.clear)
            .frame(height: 24)
            .overlay {
                if let value { Text(verbatim: Format.percent(value, digits: 0)).font(.caption2).monospacedDigit() }
            }
    }

    private func shares(_ title: LocalizedStringKey, _ rows: [Share]) -> some View {
        ChartCard(title: title, subtitle: "Revenue, last 3 months.") {
            if rows.isEmpty {
                Text("Not enough data yet.").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(rows) { row in
                        HStack(spacing: 10) {
                            Text(verbatim: row.name).lineLimit(1).frame(width: 130, alignment: .leading)
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(.quaternary)
                                    Capsule().fill(Brand.buttonGradient).frame(width: max(4, proxy.size.width * row.fraction))
                                }
                            }
                            .frame(height: 6)
                            Text(verbatim: Format.percent(row.fraction, digits: 0)).monospacedDigit().frame(width: 40, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }
}
