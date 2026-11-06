import Foundation

public enum EngineEvent: Sendable {
    case portfolio
    case alert(RadarAlert)
}

/// Keeps RevenueCat under its limit of 25 chart requests a minute, leaving room for the dashboard.
actor RateLimiter {
    private let spacing: Duration
    private var next = ContinuousClock.now

    init(spacing: Duration) {
        self.spacing = spacing
    }

    func take() async {
        let now = ContinuousClock.now
        let start = max(now, next)
        next = start + spacing
        if start > now { try? await Task.sleep(until: start, clock: .continuous) }
    }

    func pause(_ duration: Duration) {
        next = max(next, ContinuousClock.now + duration)
    }
}

/// Reads RevenueCat, keeps the reports on disk and raises alerts. The app runs one in process;
/// without the app, `mrradar hub` runs it for Remote Code. Only one runs at a time (`Hub`).
public actor Engine {
    private let source: any RevenueCatSource
    private let limiter: RateLimiter
    private let persists: Bool
    private var reports: [String: ProjectReport] = [:]
    private var alerts: [RadarAlert] = []
    private var fired: Set<String> = []
    private var listeners: [UUID: AsyncStream<EngineEvent>.Continuation] = [:]
    private var loop: Task<Void, Never>?
    private var chartTask: Task<Void, Never>?
    private var preferred: String?
    public private(set) var lastError: RadarError?
    public private(set) var refreshing = false

    public init(source: any RevenueCatSource, spacing: Duration = .seconds(3), persists: Bool = true) {
        self.source = source
        limiter = RateLimiter(spacing: spacing)
        self.persists = persists
        if persists { Self.loadCache(into: &reports, alerts: &alerts, fired: &fired) }
    }

    // MARK: Reading

    public func portfolio() -> Portfolio { Analytics.portfolio(tracked()) }
    public func report(_ id: String) -> ProjectReport? { reports[id] }
    public func recentAlerts() -> [RadarAlert] { alerts }

    private func tracked() -> [ProjectReport] {
        let wanted = RadarPreferences.load().trackedProjects
        return reports.values.filter { wanted?.contains($0.id) ?? true }
    }

    public func events() -> AsyncStream<EngineEvent> {
        AsyncStream { continuation in
            let id = UUID()
            listeners[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeListener(id) }
            }
        }
    }

    private func removeListener(_ id: UUID) { listeners[id] = nil }
    private func post(_ event: EngineEvent) { for listener in listeners.values { listener.yield(event) } }

    // MARK: Running

    public func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshOverviews()
                await self?.refreshStaleCharts()
                let minutes = RadarPreferences.load().overviewMinutes
                try? await Task.sleep(for: .seconds(max(5, minutes) * 60))
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
        chartTask?.cancel()
    }

    /// Reads everything again now. With a project, that one first.
    public func refresh(project: String? = nil) async {
        preferred = project
        if let project, let report = reports[project] {
            await refreshCharts(report.project)
        }
        await refreshOverviews()
        await refreshStaleCharts(force: project == nil)
    }

    func refreshOverviews() async {
        refreshing = true
        defer { refreshing = false }
        do {
            let projects = try await source.projects()
            let wanted = RadarPreferences.load().trackedProjects
            for project in projects where wanted?.contains(project.id) ?? true {
                let overview = try await fetchOverview(project)
                let previous = reports[project.id]
                var report = previous ?? ProjectReport(project: project, overview: overview, updatedAt: .now)
                report.project = project
                report.overview = overview
                report.updatedAt = .now
                reports[project.id] = report
                raiseAlerts(previous: previous, current: report)
            }
            let known = Set(projects.map(\.id))
            reports = reports.filter { known.contains($0.key) }
            lastError = nil
        } catch {
            lastError = (error as? RadarError) ?? .failed(error.localizedDescription)
        }
        save()
        post(.portfolio)
    }

    private func refreshStaleCharts(force: Bool = false) async {
        let hours = Double(RadarPreferences.load().chartHours)
        let stale = tracked().filter { force || ($0.chartsUpdatedAt.map { Date.now.timeIntervalSince($0) > hours * 3600 } ?? true) }
            .sorted { $0.id == preferred && $1.id != preferred }
        for report in stale where !Task.isCancelled {
            await refreshCharts(report.project)
        }
    }

    private func call(_ path: String) async throws -> Data {
        await limiter.take()
        do {
            return try await source.get(path)
        } catch RadarError.rateLimited {
            await limiter.pause(.seconds(60))
            await limiter.take()
            return try await source.get(path)
        }
    }

    private func chart(_ project: String, _ name: String, resolution: Int, days: Int, segment: String? = nil, now: Date) async throws -> Chart {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let start = formatter.string(from: now.addingTimeInterval(-Double(days) * 86400))
        var path = "/projects/\(project)/charts/\(name)?resolution=\(resolution)&start_date=\(start)&end_date=\(formatter.string(from: now))"
        if let segment { path += "&segment=\(segment)" }
        return try JSONDecoder().decode(Chart.self, from: try await call(path))
    }

    private func fetchOverview(_ project: RCProject) async throws -> Overview {
        struct Envelope: Decodable {
            struct Metric: Decodable {
                var id: String
                var value: Double
            }
            var currency: String?
            var metrics: [Metric]
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: try await call("/projects/\(project.id)/metrics/overview"))
        func value(_ id: String) -> Double { envelope.metrics.first { $0.id == id }?.value ?? 0 }
        return Overview(
            currency: envelope.currency ?? "USD", mrr: value("mrr"), revenue28: value("revenue"),
            activeSubscriptions: value("active_subscriptions"), activeTrials: value("active_trials"),
            newCustomers28: value("new_customers"), activeUsers28: value("active_users")
        )
    }

    func refreshCharts(_ project: RCProject) async {
        guard var report = reports[project.id] else { return }
        let previous = report
        let now = Date.now
        do {
            let id = project.id
            let revenue = try await chart(id, "revenue", resolution: 0, days: 400, now: now)
            let mrr = try await chart(id, "mrr", resolution: 0, days: 120, now: now)
            let movement = try await chart(id, "mrr_movement", resolution: 1, days: 182, now: now)
            let churn = try await chart(id, "churn", resolution: 1, days: 182, now: now)
            let trials = try await chart(id, "trial_conversion_rate", resolution: 1, days: 182, now: now)
            let refunds = try await chart(id, "refund_rate", resolution: 2, days: 62, now: now)
            let retention = try await chart(id, "subscription_retention", resolution: 2, days: 400, now: now)
            let countries = try await chart(id, "revenue", resolution: 2, days: 92, segment: "country", now: now)
            let stores = try await chart(id, "revenue", resolution: 2, days: 92, segment: "store", now: now)

            report.revenueDaily = revenue.series("Revenue").filter { !$0.incomplete }.map { DatedValue(date: $0.date!, value: $0.value) }
            report.mrrDaily = mrr.series("MRR").filter { !$0.incomplete }.map { DatedValue(date: $0.date!, value: $0.value) }
            report.movement = Self.movement(movement)
            report.churnWeekly = churn.series("Churn Rate").filter { !$0.incomplete }.map { DatedValue(date: $0.date!, value: $0.value) }
            report.trialsWeekly = Self.trials(trials)
            report.retention = retention.retentionRows()
            report.countries = countries.shares()
            report.stores = stores.shares()
            report.anomalies = Analytics.anomalies(report.revenueDaily)
            let refundRate = refunds.series("Refund Rate").last { !$0.incomplete }.map { $0.value / 100 }
            report.insights = Analytics.insights(
                overview: report.overview, revenueDaily: report.revenueDaily, mrrDaily: report.mrrDaily,
                movement: report.movement, churnWeekly: report.churnWeekly, trialsWeekly: report.trialsWeekly,
                countries: report.countries, refundRate: refundRate, now: now
            )
            report.chartsUpdatedAt = now
            reports[project.id] = report
            raiseAlerts(previous: previous, current: report)
            lastError = nil
            save()
            post(.portfolio)
        } catch {
            lastError = (error as? RadarError) ?? .failed(error.localizedDescription)
        }
    }

    static func movement(_ chart: Chart) -> [MovementWeek] {
        func by(_ name: String) -> [Date: Double] {
            Dictionary(chart.series(name).map { ($0.date!, $0.value) }, uniquingKeysWith: { a, _ in a })
        }
        let new = by("New MRR"), back = by("Resubscription MRR"), up = by("Expansion MRR")
        let churned = by("Churned MRR"), down = by("Contraction MRR")
        return new.keys.sorted().map { date in
            MovementWeek(
                date: date, gained: new[date, default: 0] + back[date, default: 0] + up[date, default: 0],
                lost: abs(churned[date, default: 0]) + abs(down[date, default: 0])
            )
        }
    }

    static func trials(_ chart: Chart) -> [TrialWeek] {
        let starts = chart.series("Trial Starts")
        let conversions = Dictionary(chart.series("Conversions").map { ($0.date!, $0.value) }, uniquingKeysWith: { a, _ in a })
        let completed = Dictionary(chart.series("Completed Trials").map { ($0.date!, $0.value) }, uniquingKeysWith: { a, _ in a })
        return starts.map {
            TrialWeek(date: $0.date!, starts: $0.value, conversions: conversions[$0.date!, default: 0], completed: completed[$0.date!, default: 0])
        }
    }

    private func raiseAlerts(previous: ProjectReport?, current: ProjectReport) {
        let rules = RadarPreferences.load().alerts
        for alert in AlertRulesEngine.alerts(previous: previous, current: current, rules: rules, now: .now) where !fired.contains(alert.id) {
            fired.insert(alert.id)
            alerts.insert(alert, at: 0)
            post(.alert(alert))
        }
        alerts = Array(alerts.prefix(100))
    }

    // MARK: Disk

    private struct AlertFile: Codable {
        var alerts: [RadarAlert]
        var fired: [String]
    }

    private static func loadCache(into reports: inout [String: ProjectReport], alerts: inout [RadarAlert], fired: inout Set<String>) {
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: RadarPaths.cache.appendingPathComponent("reports.json")),
           let list = try? decoder.decode([ProjectReport].self, from: data) {
            reports = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        }
        if let data = try? Data(contentsOf: RadarPaths.alerts), let file = try? decoder.decode(AlertFile.self, from: data) {
            alerts = file.alerts
            fired = Set(file.fired)
        }
    }

    private func save() {
        guard persists else { return }
        let manager = FileManager.default
        try? manager.createDirectory(at: RadarPaths.cache, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(Array(reports.values)) {
            try? data.write(to: RadarPaths.cache.appendingPathComponent("reports.json"), options: [.atomic, .completeFileProtection])
        }
        if let data = try? encoder.encode(AlertFile(alerts: alerts, fired: Array(fired.suffix(2000)))) {
            try? data.write(to: RadarPaths.alerts, options: .atomic)
        }
    }

    /// Forgets everything, on sign-out.
    public func reset() {
        reports = [:]
        alerts = []
        fired = []
        try? FileManager.default.removeItem(at: RadarPaths.cache)
        try? FileManager.default.removeItem(at: RadarPaths.alerts)
        post(.portfolio)
    }
}
