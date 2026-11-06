import RadarKit
import SwiftUI

/// Everything MRRadar needs before it opens. Required steps can't be passed until they are done.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            rail
            Divider()
            Group {
                switch model.step {
                case .welcome: WelcomeStep()
                case .tool: ToolStep()
                case .account: AccountStep()
                case .projects: ProjectsStep()
                case .notifications: NotificationsStep()
                case .done: DoneStep()
                }
            }
            .frame(maxWidth: 560)
            .padding(36)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(BrandBackground())
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                IconBadge(symbol: "chart.line.uptrend.xyaxis", size: 30)
                Text(verbatim: "MRRadar").font(.title2.bold())
            }
            .padding(.bottom, 18)
            ForEach(SetupStep.allCases, id: \.self) { step in
                HStack(spacing: 10) {
                    Image(systemName: step < model.step ? "checkmark.circle.fill" : (step == model.step ? "circle.inset.filled" : "circle"))
                        .foregroundStyle(step <= model.step ? Brand.emerald : .secondary)
                    Text(title(step))
                        .fontWeight(step == model.step ? .semibold : .regular)
                        .foregroundStyle(step == model.step ? .primary : .secondary)
                }
            }
            Spacer()
        }
        .padding(24)
        .frame(width: 230, alignment: .leading)
    }

    private func title(_ step: SetupStep) -> LocalizedStringKey {
        switch step {
        case .welcome: "Welcome"
        case .tool: "RevenueCat CLI"
        case .account: "Sign in"
        case .projects: "Your apps"
        case .notifications: "Notifications"
        case .done: "Ready"
        }
    }
}

private struct StepHeader: View {
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            IconBadge(symbol: symbol, size: 44)
            Text(title).font(.largeTitle.bold())
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ErrorLine: View {
    let text: String?

    var body: some View {
        if let text {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Brand.coral)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct WelcomeStep: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(
                symbol: "chart.bar.xaxis", title: "See your subscription business your way",
                text: "MRRadar lays out all your RevenueCat apps together, with numbers the dashboard doesn't show: forecasts, month-end pace, MRR quick ratio, implied LTV and alerts."
            )
            VStack(alignment: .leading, spacing: 10) {
                Label("Runs on your Mac, with no server and no account of its own.", systemImage: "lock.shield")
                Label("Uses the official RevenueCat CLI, which keeps your sign-in.", systemImage: "terminal")
                Label("Sends nothing anywhere except your requests to RevenueCat.", systemImage: "eye.slash")
            }
            Button("Get Started") { model.step = .tool }.buttonStyle(GradientButtonStyle())
        }
    }
}

private struct ToolStep: View {
    @Environment(AppModel.self) private var model
    @State private var found: String?
    @State private var version: String?
    @State private var checking = true
    @State private var installing = false
    @State private var status = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(
                symbol: "terminal", title: "Install the RevenueCat CLI",
                text: "MRRadar reads your data through rc, RevenueCat's official command line tool. It's free and open source."
            )
            if checking {
                ProgressView()
            } else if let found {
                Label {
                    VStack(alignment: .leading) {
                        Text("rc \(versionText) is installed")
                        Text(verbatim: found).font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.emerald)
                }
                Button("Continue") { model.step = .account }.buttonStyle(GradientButtonStyle())
            } else {
                Text("MRRadar uses Homebrew if you have it. Otherwise it downloads the official release from GitHub, checks it against the published checksum and keeps it in its own folder.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if installing {
                    HStack { ProgressView().controlSize(.small); Text(verbatim: status).foregroundStyle(.secondary) }
                } else {
                    Button("Install") { install() }.buttonStyle(GradientButtonStyle())
                }
                ErrorLine(text: error)
            }
        }
        .task { await look() }
    }

    private var versionText: String { version ?? "" }

    private func look() async {
        checking = true
        found = await ShellEnvironment.shared.which("rc")
        if found != nil { version = await model.cli.version() }
        checking = false
    }

    private func install() {
        installing = true
        error = nil
        Task {
            do {
                try await ToolInstaller.installRevenueCatCLI { text in
                    Task { @MainActor in status = text }
                }
                await look()
            } catch {
                self.error = error.localizedDescription
            }
            installing = false
        }
    }
}

private struct AccountStep: View {
    @Environment(AppModel.self) private var model
    @State private var signedIn = false
    @State private var checking = true
    @State private var waiting = false
    @State private var useKey = false
    @State private var key = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(
                symbol: "person.badge.key", title: "Sign in to RevenueCat",
                text: "Your browser opens RevenueCat. MRRadar never sees your password, and the CLI keeps the sign-in on this Mac."
            )
            if checking {
                ProgressView()
            } else if signedIn {
                Label("Signed in", systemImage: "checkmark.circle.fill").foregroundStyle(Brand.emerald)
                Button("Continue") { model.step = .projects }.buttonStyle(GradientButtonStyle())
            } else if waiting {
                HStack { ProgressView().controlSize(.small); Text("Waiting for you to approve in the browser…").foregroundStyle(.secondary) }
            } else {
                Button("Sign In with Browser") { browser() }.buttonStyle(GradientButtonStyle())
                DisclosureGroup("Use a secret API key instead", isExpanded: $useKey) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Create a REST API v2 secret key in RevenueCat, with read access to charts and projects. It stays in your Keychain.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        SecureField("sk_…", text: $key).textFieldStyle(.roundedBorder)
                        Button("Use This Key") { saveKey() }
                            .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.top, 6)
                }
                ErrorLine(text: error)
            }
        }
        .task {
            signedIn = await model.cli.isSignedIn()
            checking = false
        }
    }

    private func browser() {
        waiting = true
        error = nil
        Task {
            do {
                try await model.cli.signIn()
                signedIn = true
            } catch {
                self.error = String(localized: "The sign-in didn't finish. Try again.")
            }
            waiting = false
        }
    }

    private func saveKey() {
        error = nil
        Task {
            do {
                try KeychainKey.save(key.trimmingCharacters(in: .whitespaces))
                key = ""
                signedIn = await model.cli.isSignedIn()
                if !signedIn {
                    KeychainKey.delete()
                    error = String(localized: "RevenueCat didn't accept this key.")
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct ProjectsStep: View {
    @Environment(AppModel.self) private var model
    @State private var projects: [RCProject] = []
    @State private var chosen: Set<String> = []
    @State private var loading = true
    @State private var verifying = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(symbol: "square.grid.2x2", title: "Choose your apps", text: "MRRadar follows the projects you pick here. You can change this later in Settings.")
            if loading {
                ProgressView()
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(projects) { project in
                            Toggle(isOn: Binding(
                                get: { chosen.contains(project.id) },
                                set: { if $0 { chosen.insert(project.id) } else { chosen.remove(project.id) } }
                            )) {
                                HStack(spacing: 10) {
                                    ProjectIcon(project: project, size: 26)
                                    Text(verbatim: project.name)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 260)
                ErrorLine(text: error)
                Button(verifying ? "Checking access…" : "Continue") { verify() }
                    .buttonStyle(GradientButtonStyle())
                    .disabled(chosen.isEmpty || verifying)
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            projects = try await model.cli.projects()
            chosen = Set(model.preferences.trackedProjects ?? projects.map(\.id))
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    /// A key without chart permission would give an empty app, so that's caught here.
    private func verify() {
        verifying = true
        error = nil
        Task {
            let first = projects.first { chosen.contains($0.id) }
            if let first, await !model.cli.canReadCharts(first.id) {
                error = String(localized: "This sign-in can't read charts. Use a key with the charts_metrics permission.")
            } else {
                model.preferences.trackedProjects = chosen.count == projects.count ? nil : Array(chosen)
                model.savePreferences()
                model.step = .notifications
            }
            verifying = false
        }
    }
}

private struct NotificationsStep: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(
                symbol: "bell.badge", title: "Stay on top of your numbers",
                text: "MRRadar tells you about new subscribers, falling MRR, unusual days, refunds and churn. With Remote Code, the same alerts reach your iPhone."
            )
            HStack {
                Button("Turn On Notifications") {
                    Task {
                        model.preferences.notifyOnMac = await Notifier.requestPermission()
                        model.savePreferences()
                        model.step = .done
                    }
                }
                .buttonStyle(GradientButtonStyle())
                Button("Not Now") {
                    model.preferences.notifyOnMac = false
                    model.savePreferences()
                    model.step = .done
                }
            }
        }
    }
}

private struct DoneStep: View {
    @Environment(AppModel.self) private var model
    @State private var startAtLogin = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(
                symbol: "checkmark.seal", title: "You're all set",
                text: "MRRadar lives in your menu bar and reads your numbers in the background. The first full report takes a few minutes, because RevenueCat limits how fast charts can be read."
            )
            Toggle("Open MRRadar at login", isOn: $startAtLogin)
            Button("Open MRRadar") {
                try? LaunchAtLogin.setEnabled(startAtLogin)
                Task { await model.finishSetup() }
            }
            .buttonStyle(GradientButtonStyle())
        }
    }
}
