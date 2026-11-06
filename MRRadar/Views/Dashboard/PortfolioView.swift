import Charts
import RadarKit
import SwiftUI

/// Every app side by side, which the RevenueCat dashboard shows one project at a time.
struct PortfolioView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ErrorBanner()
                if model.portfolio.totals.isEmpty {
                    ProgressView("Reading your numbers…").padding(.top, 120)
                }
                ForEach(model.portfolio.totals) { total in
                    summary(total)
                }
                table
            }
            .padding(20)
        }
        .navigationTitle(Text("Portfolio"))
    }

    @ViewBuilder private func summary(_ total: PortfolioTotal) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            KPICard(title: "MRR", value: Format.money(total.mrr, total.currency), detail: total.mrrChange30.map(Format.signedPercent), positive: total.mrrChange30.map { $0 >= 0 })
            KPICard(title: "ARR", value: Format.money(total.mrr * 12, total.currency))
            KPICard(title: "Subscribers", value: Format.count(total.activeSubscriptions))
            KPICard(title: "Active trials", value: Format.count(total.activeTrials))
        }
        if total.mrr == 0, total.revenue28 == 0 {
            Label("No revenue yet. The charts fill in with your first subscribers.", systemImage: "leaf").font(.callout).glassCard(padding: 12)
        }
        HStack(alignment: .top, spacing: 12) {
            ChartCard(title: "Revenue, all apps", subtitle: "Last 90 days") {
                let days = Array(total.revenueDaily.suffix(90))
                Chart(days) { day in
                    AreaMark(x: .value("Date", day.date), y: .value("Revenue", day.value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [Brand.emerald.opacity(0.45), Brand.emerald.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Date", day.date), y: .value("Revenue", day.value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Brand.emerald)
                }
                .frame(height: 210)
            }
            ChartCard(title: "Where MRR comes from") {
                if total.mrrShare.isEmpty {
                    Text("Not enough data yet.").font(.callout).foregroundStyle(.secondary).frame(height: 210)
                } else {
                    Chart(total.mrrShare) { share in
                        SectorMark(angle: .value("MRR", share.value), innerRadius: .ratio(0.62), angularInset: 1.5)
                            .cornerRadius(3)
                            .foregroundStyle(by: .value("App", share.name))
                    }
                    .chartLegend(position: .bottom, alignment: .center)
                    .frame(height: 210)
                }
            }
            .frame(maxWidth: 320)
        }
    }

    private var table: some View {
        ChartCard(title: "Apps compared", subtitle: "Sorted by MRR. Quick ratio is MRR won per unit lost over 8 weeks; above 4 is strong, below 1 is shrinking.") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
                GridRow {
                    Text("App")
                    Text("MRR").gridColumnAlignment(.trailing)
                    Text("30 days").gridColumnAlignment(.trailing)
                    Text("Quick ratio").gridColumnAlignment(.trailing)
                    Text("Churn / mo").gridColumnAlignment(.trailing)
                    Text("Implied LTV").gridColumnAlignment(.trailing)
                    Text("Month-end pace").gridColumnAlignment(.trailing)
                    Text("Trials").gridColumnAlignment(.trailing)
                    Text("New users").gridColumnAlignment(.trailing)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                Divider()
                ForEach(model.portfolio.reports) { report in
                    let insights = report.insights, currency = report.overview.currency
                    GridRow {
                        Button { model.selection = .project(report.id) } label: {
                            HStack(spacing: 8) {
                                ProjectIcon(project: report.project, size: 22)
                                Text(verbatim: report.project.name).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        Text(verbatim: Format.money(report.overview.mrr, currency))
                        Text(verbatim: insights.mrrChange30.map(Format.signedPercent) ?? "—")
                            .foregroundStyle(insights.mrrChange30.map { $0 >= 0 ? Brand.emerald : Brand.coral } ?? .secondary)
                        Text(verbatim: insights.quickRatio.map(Format.ratio) ?? "—")
                        Text(verbatim: insights.monthlyChurn.map { Format.percent($0) } ?? "—")
                        Text(verbatim: insights.impliedLTV.map { Format.money($0, currency) } ?? "—")
                        Text(verbatim: insights.monthEndPace.map { Format.money($0, currency) } ?? "—")
                        Text(verbatim: Format.count(report.overview.activeTrials))
                        Text(verbatim: Format.count(report.overview.newCustomers28))
                    }
                    .monospacedDigit()
                }
            }
        }
    }
}
