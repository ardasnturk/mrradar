import AppKit
import RadarKit
import Observation
import UserNotifications

enum SetupStep: Int, CaseIterable, Comparable {
    case welcome, tool, account, projects, notifications, done
    static func < (a: SetupStep, b: SetupStep) -> Bool { a.rawValue < b.rawValue }
}

enum Phase: Equatable {
    case checking
    case setup
    case ready
}

/// The app's state. Until every required step is done `phase` stays `.setup`, the window shows
/// onboarding and the menu offers only to finish it. A step that later breaks, such as an
/// expired sign-in, brings the app back to that step.
@MainActor
@Observable
final class AppModel {
    static let demo = CommandLine.arguments.contains("--demo")

    private(set) var phase = Phase.checking
    var step = SetupStep.welcome
    var preferences = RadarPreferences.load()
    private(set) var portfolio = Portfolio.empty
    private(set) var alerts: [RadarAlert] = []
    private(set) var selectedReport: ProjectReport?
    private(set) var isRefreshing = false
    private(set) var lastError: String?
    var selection: SidebarItem? = .portfolio
    var onOpenWindow: (() -> Void)?

    let cli = RevenueCatCLI()
    private var engine: Engine?
    private var hub: Hub?
    private var delegate: NotificationDelegate?
    private var listener: Task<Void, Never>?

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    func launch() async {
        let delegate = NotificationDelegate { [weak self] project in self?.show(project: project) }
        self.delegate = delegate
        UNUserNotificationCenter.current().delegate = delegate
        await check()
        #if DEBUG
        if let folder = Snapshots.folder { await Snapshots.run(self, to: folder) }
        #endif
    }

    /// Finds the first required step that isn't done.
    func check() async {
        if Self.demo {
            await becomeReady()
            return
        }
        phase = .checking
        let missing: SetupStep? = if await ShellEnvironment.shared.which("rc") == nil {
            .tool
        } else if await !cli.isSignedIn() {
            .account
        } else if !preferences.setupFinished {
            nil
        } else {
            .done
        }
        switch missing {
        case .done:
            await becomeReady()
        case nil:
            phase = .setup
            step = max(step, .welcome)
            openWindow()
        case let step?:
            stopEngine()
            phase = .setup
            self.step = preferences.setupFinished ? step : .welcome
            openWindow()
        }
    }

    func finishSetup() async {
        preferences.setupFinished = true
        savePreferences()
        await becomeReady()
    }

    func savePreferences() {
        try? preferences.save()
    }

    private func becomeReady() async {
        phase = .ready
        guard engine == nil else { return }
        await Hub.askLiveHubToYield()
        let engine = Engine(
            source: Self.demo ? DemoSource() : cli, spacing: Self.demo ? .milliseconds(1) : .seconds(3), persists: !Self.demo
        )
        self.engine = engine
        let hub = Hub(engine: engine, demo: Self.demo, version: version) {}
        try? hub.start()
        self.hub = hub
        portfolio = await engine.portfolio()
        alerts = await engine.recentAlerts()
        let events = await engine.events()
        listener = Task { [weak self] in
            for await event in events {
                await self?.handle(event)
            }
        }
        await engine.start()
    }

    private func stopEngine() {
        listener?.cancel()
        listener = nil
        hub?.stop()
        hub = nil
        Task { [engine] in await engine?.stop() }
        engine = nil
    }

    private func handle(_ event: EngineEvent) async {
        guard let engine else { return }
        switch event {
        case .portfolio:
            portfolio = await engine.portfolio()
            alerts = await engine.recentAlerts()
            if let id = selectedReport?.id { selectedReport = await engine.report(id) }
            let failure = await engine.lastError
            lastError = failure?.errorDescription
            if failure == .signedOut || failure == .cliMissing { await check() }
        case .alert(let alert):
            alerts = await engine.recentAlerts()
            if preferences.notifyOnMac { Notifier.post(alert) }
        }
    }

    func select(project id: String) async {
        selectedReport = await engine?.report(id)
        if selectedReport?.chartsUpdatedAt == nil {
            Task { await engine?.refresh(project: id) }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            await engine?.refresh(project: selectedReport?.id)
            isRefreshing = false
        }
    }

    func show(project id: String) {
        selection = .project(id)
        openWindow()
    }

    func openWindow() {
        onOpenWindow?()
    }

    func signOut() async {
        try? await cli.signOut()
        await engine?.reset()
        preferences.setupFinished = false
        savePreferences()
        stopEngine()
        portfolio = .empty
        alerts = []
        step = .welcome
        await check()
    }

    func quit() {
        hub?.stop()
        NSApp.terminate(nil)
    }
}

enum SidebarItem: Hashable {
    case portfolio
    case alerts
    case project(String)
}
