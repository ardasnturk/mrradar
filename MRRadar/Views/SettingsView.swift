import RadarKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }
            AlertsTab().tabItem { Label("Alerts", systemImage: "bell") }
            AccountTab().tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        .frame(width: 520, height: 420)
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
