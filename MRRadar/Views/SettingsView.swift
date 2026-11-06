import RadarKit
import SwiftUI

struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general, alerts, account, updates
        var id: String { rawValue }
    }

    @State private var pane: Pane = .general

    var body: some View {
        HStack(spacing: 0) {
            List(Pane.allCases, selection: $pane) { pane in
                Label {
                    Text(title(pane))
                } icon: {
                    IconBadge(symbol: symbol(pane), colors: colors(pane), size: 22)
                }
                .padding(.vertical, 3)
                .tag(pane)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .frame(width: 210)
            .background(.thinMaterial)
            Divider()
            VStack(spacing: 0) {
                PaneHeader(symbol: symbol(pane), colors: colors(pane), title: title(pane), subtitle: subtitle(pane))
                detail.scrollContentBackground(.hidden)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BrandBackground())
        }
        .frame(width: 780, height: 560)
    }

    @ViewBuilder private var detail: some View {
        switch pane {
        case .general: GeneralTab()
        case .alerts: AlertsTab()
        case .account: AccountTab()
        case .updates: UpdatesTab()
        }
    }

    private func title(_ pane: Pane) -> LocalizedStringKey {
        switch pane {
        case .general: "General"
        case .alerts: "Alerts"
        case .account: "Account"
        case .updates: "Updates"
        }
    }

    private func subtitle(_ pane: Pane) -> LocalizedStringKey {
        switch pane {
        case .general: "When MRRadar opens and how often it reads."
        case .alerts: "Which notifications you get, and when."
        case .account: "Your sign-in and the command line tool."
        case .updates: "The version you have, and newer ones."
        }
    }

    private func symbol(_ pane: Pane) -> String {
        switch pane {
        case .general: "gearshape.fill"
        case .alerts: "bell.fill"
        case .account: "person.crop.circle.fill"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }

    private func colors(_ pane: Pane) -> [Color] {
        switch pane {
        case .general: [Color.gray, Color.gray.opacity(0.7)]
        case .alerts: [Color.red, Color.orange]
        case .account: [Color.blue, Color.teal]
        case .updates: [Color.green, Color.teal]
        }
    }
}

private struct PaneHeader: View {
    let symbol: String
    let colors: [Color]
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(symbol: symbol, colors: colors, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title2.weight(.bold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 6)
    }
}

private struct UpdatesTab: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppUpdater.automaticKey) private var automatic = true

    var body: some View {
        let updater = model.updater
        Form {
            Section {
                LabeledContent("Installed version", value: updater.currentVersion)
                UpdateStatusView(updater: updater)
                Toggle("Check for updates automatically", isOn: $automatic)
            } footer: {
                Text("MRRadar looks for a new release on GitHub once a day. Updates are only installed when you click Install; they are checked for Apple's notarization and the same developer signature first.")
            }
            if case .available = updater.state, !updater.releaseNotes.isEmpty {
                Section {
                    ScrollView {
                        Text(LocalizedStringKey(updater.releaseNotes))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 180)
                } header: {
                    Text("What's new")
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// The update state with its action: check, install, progress or error.
struct UpdateStatusView: View {
    let updater: AppUpdater

    var body: some View {
        HStack(spacing: 10) {
            switch updater.state {
            case .idle:
                Text("Not checked yet").foregroundStyle(.secondary)
                Spacer()
                checkButton
            case .checking:
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
                Spacer()
            case .upToDate:
                Label("MRRadar is up to date", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                checkButton
            case .available(let release):
                Label {
                    Text("Version \(release.version.description) is available")
                } icon: {
                    Image(systemName: "sparkles").foregroundStyle(Color.purple)
                }
                Spacer()
                Button("Install and Relaunch") { Task { await updater.installUpdate() } }
                    .buttonStyle(.borderedProminent)
            case .downloading(let progress):
                ProgressView(value: progress) {
                    Text("Downloading…")
                }
            case .installing:
                ProgressView().controlSize(.small)
                Text("Installing…").foregroundStyle(.secondary)
                Spacer()
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                checkButton
            }
        }
    }

    private var checkButton: some View {
        Button("Check Now") { Task { await updater.checkForUpdates(userInitiated: true) } }
    }
}

private struct GeneralTab: View {
    @Environment(AppModel.self) private var model
    @State private var startAtLogin = LaunchAtLogin.isEnabled
    @State private var projects: [RCProject] = []

    var body: some View {
        @Bindable var model = model
        Form {
            Toggle("Open MRRadar at login", isOn: $startAtLogin)
                .onChange(of: startAtLogin) { _, value in try? LaunchAtLogin.setEnabled(value) }
            Picker("Read headline numbers", selection: $model.preferences.overviewMinutes) {
                Text("Every 5 minutes").tag(5)
                Text("Every 15 minutes").tag(15)
                Text("Every hour").tag(60)
            }
            Picker("Read full charts", selection: $model.preferences.chartHours) {
                Text("Every 3 hours").tag(3)
                Text("Every 6 hours").tag(6)
                Text("Once a day").tag(24)
            }
            Section("Apps") {
                ForEach(projects) { project in
                    Toggle(project.name, isOn: Binding(
                        get: { model.preferences.trackedProjects?.contains(project.id) ?? true },
                        set: { on in
                            var list = model.preferences.trackedProjects ?? projects.map(\.id)
                            if on { list.append(project.id) } else { list.removeAll { $0 == project.id } }
                            model.preferences.trackedProjects = Set(list).count == projects.count ? nil : list
                        }
                    ))
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.preferences) { _, _ in model.savePreferences() }
        .task { projects = (try? await model.cli.projects()) ?? [] }
    }
}

private struct AlertsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Toggle("Notify me on this Mac", isOn: $model.preferences.notifyOnMac)
            Section("Tell me about") {
                ForEach(RadarAlert.Kind.allCases, id: \.self) { kind in
                    Toggle(name(kind), isOn: Binding(
                        get: { model.preferences.alerts.isOn(kind) },
                        set: { model.preferences.alerts.enabled[kind] = $0 }
                    ))
                }
            }
            Section("Thresholds") {
                Picker("MRR drop in 7 days", selection: $model.preferences.alerts.mrrDrop) {
                    Text(verbatim: Format.percent(0.03)).tag(0.03)
                    Text(verbatim: Format.percent(0.05)).tag(0.05)
                    Text(verbatim: Format.percent(0.1)).tag(0.1)
                }
                Picker("Refund rate", selection: $model.preferences.alerts.refundRate) {
                    Text(verbatim: Format.percent(0.03)).tag(0.03)
                    Text(verbatim: Format.percent(0.05)).tag(0.05)
                    Text(verbatim: Format.percent(0.1)).tag(0.1)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.preferences) { _, _ in model.savePreferences() }
    }

    private func name(_ kind: RadarAlert.Kind) -> LocalizedStringKey {
        switch kind {
        case .newSubscribers: "New subscribers"
        case .mrrDrop: "Falling MRR"
        case .mrrMilestone: "MRR milestones"
        case .revenueSpike: "Unusually good days"
        case .revenueDip: "Unusually quiet days"
        case .refundSpike: "High refund rate"
        case .churnSpike: "Rising churn"
        }
    }
}

private struct AccountTab: View {
    @Environment(AppModel.self) private var model
    @State private var version: String?
    @State private var path: String?

    var body: some View {
        Form {
            LabeledContent("RevenueCat CLI") {
                Text(verbatim: version ?? "—")
            }
            if let path {
                LabeledContent("Location") { Text(verbatim: path).textSelection(.enabled) }
            }
            Button("Sign Out…", role: .destructive) {
                Task { await model.signOut() }
            }
            Section {
                LabeledContent("MRRadar") { Text(verbatim: model.version) }
            } footer: {
                Text("MRRadar is not affiliated with RevenueCat.")
            }
        }
        .formStyle(.grouped)
        .task {
            path = await ShellEnvironment.shared.which("rc")
            version = await model.cli.version()
        }
    }
}
