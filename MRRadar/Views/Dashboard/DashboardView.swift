import RadarKit
import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selection) {
                Label("Portfolio", systemImage: "chart.pie").tag(SidebarItem.portfolio)
                Label("Alerts", systemImage: "bell").tag(SidebarItem.alerts)
                Section("Apps") {
                    ForEach(model.portfolio.reports) { report in
                        HStack(spacing: 8) {
                            ProjectIcon(project: report.project, size: 20)
                            Text(verbatim: report.project.name).lineLimit(1)
                        }
                        .tag(SidebarItem.project(report.id))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } detail: {
            ZStack {
                BrandBackground()
                switch model.selection ?? .portfolio {
                case .portfolio: PortfolioView()
                case .alerts: AlertsView()
                case .project(let id): ProjectView(id: id).id(id)
                }
            }
            .toolbar {
                ToolbarItem {
                    Button { model.refresh() } label: {
                        if model.isRefreshing { ProgressView().controlSize(.small) } else { Label("Refresh", systemImage: "arrow.clockwise") }
                    }
                    .help(Text("Refresh"))
                }
            }
        }
    }
}

/// Reports whatever went wrong on the last read, above the content it may have left stale.
struct ErrorBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let error = model.lastError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(Brand.coral)
                .glassCard(padding: 10)
        }
    }
}

struct AlertsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if model.alerts.isEmpty {
                    ContentUnavailableView("No alerts yet", systemImage: "bell.slash", description: Text("MRRadar tells you here when a number moves."))
                        .padding(.top, 80)
                }
                ForEach(model.alerts) { alert in
                    Button { model.show(project: alert.projectID) } label: {
                        HStack(spacing: 12) {
                            IconBadge(symbol: alert.symbol, colors: alert.isGood ? [Brand.emerald, Brand.teal] : [Brand.coral, Brand.gold], size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: alert.title).fontWeight(.medium)
                                Text(verbatim: alert.body).font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(alert.date, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .glassCard(padding: 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(Text("Alerts"))
    }
}

/// One headline number.
struct KPICard: View {
    let title: LocalizedStringKey
    let value: String
    var detail: String?
    var positive: Bool?
    var help: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
            Text(verbatim: value).font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(verbatim: detail ?? " ")
                .font(.caption.weight(.medium))
                .foregroundStyle(positive.map { $0 ? Brand.emerald : Brand.coral } ?? .secondary)
                .lineLimit(1)
        }
        .glassCard(padding: 12)
        .help(help.map { Text($0) } ?? Text(verbatim: ""))
    }
}

struct ChartCard<Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            content
        }
        .glassCard()
    }
}
