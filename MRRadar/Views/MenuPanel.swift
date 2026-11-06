import Charts
import RadarKit
import SwiftUI

struct MenuPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 10) {
            if model.phase == .ready {
                header
                apps
                if let alert = model.alerts.first { alertRow(alert) }
            } else {
                setup
            }
            footer
        }
        .padding(10)
        .frame(width: 350)
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                IconBadge(symbol: "chart.line.uptrend.xyaxis")
                Text(verbatim: "MRRadar").font(.headline)
            }
            Text("Finish setup to see your numbers.").foregroundStyle(.secondary)
            Button("Finish Setup") { model.openWindow() }.buttonStyle(GradientButtonStyle())
        }
        .glassCard()
    }

    private var header: some View {
        let total = model.portfolio.totals.first
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(verbatim: "MRRadar").font(.headline)
                Spacer()
                if let date = model.portfolio.updatedAt {
                    Text(date, format: .relative(presentation: .named)).font(.caption)
                }
            }
            if let total {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: Format.money(total.mrr, total.currency)).font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("MRR").font(.caption.weight(.medium))
                    Spacer()
                    if let change = total.mrrChange30 {
                        Text(verbatim: Format.signedPercent(change)).font(.callout.weight(.semibold))
                    }
                }
                HStack(spacing: 7) {
                    stat(Format.count(total.activeSubscriptions), "subscribers")
                    stat(Format.count(total.activeTrials), "trials")
                    stat(Format.money(total.revenue28, total.currency, compact: true), "28 days")
                }
            } else {
                Text("Reading your numbers…").font(.callout)
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func stat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: value).font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var apps: some View {
        VStack(spacing: 2) {
            ForEach(model.portfolio.reports.prefix(6)) { report in
                Button {
                    model.show(project: report.id)
                } label: {
                    HStack(spacing: 9) {
                        ProjectIcon(project: report.project, size: 26)
                        Text(verbatim: report.project.name).lineLimit(1)
                        Spacer(minLength: 6)
                        Sparkline(values: report.mrrDaily.suffix(30).map(\.value)).frame(width: 54, height: 18)
                        Text(verbatim: Format.money(report.overview.mrr, report.overview.currency, compact: true))
                            .monospacedDigit().frame(minWidth: 58, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
            }
        }
        .glassCard(padding: 10)
    }

    private func alertRow(_ alert: RadarAlert) -> some View {
        HStack(spacing: 9) {
            Image(systemName: alert.symbol).foregroundStyle(alert.isGood ? Brand.emerald : Brand.coral)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: alert.title).font(.callout.weight(.medium)).lineLimit(1)
                Text(verbatim: alert.body).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .glassCard(padding: 10)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if model.phase == .ready {
                Button("Open MRRadar") { model.openWindow() }
                Button { model.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise").labelStyle(.iconOnly) }
                    .help(Text("Refresh"))
            }
            Spacer()
            Button { SettingsWindow.show(using: openSettings) } label: { Label("Settings…", systemImage: "gearshape").labelStyle(.iconOnly) }
                .help(Text("Settings…"))
            Button { model.quit() } label: { Label("Quit MRRadar", systemImage: "power").labelStyle(.iconOnly) }
                .help(Text("Quit MRRadar"))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 6)
    }
}

/// A tiny line with no axes.
struct Sparkline: View {
    let values: [Double]

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { item in
            LineMark(x: .value("Day", item.offset), y: .value("Value", item.element))
                .interpolationMethod(.monotone)
                .foregroundStyle((values.last ?? 0) >= (values.first ?? 0) ? Brand.emerald : Brand.coral)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .accessibilityHidden(true)
    }
}
