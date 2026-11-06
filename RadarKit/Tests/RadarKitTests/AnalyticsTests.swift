import Foundation
import Testing
@testable import RadarKit

private let day: TimeInterval = 86400
private func days(_ values: [Double], end: Date = Date(timeIntervalSince1970: 1_790_000_000)) -> [DatedValue] {
    values.enumerated().map { DatedValue(date: end.addingTimeInterval(Double($0.offset - values.count + 1) * day), value: $0.element) }
}
private let overview = Overview(currency: "USD", mrr: 1000, revenue28: 1100, activeSubscriptions: 100, activeTrials: 20, newCustomers28: 0, activeUsers28: 0)

@Suite struct AnalyticsTests {
    @Test func trendFollowsAStraightLine() {
        let line = Analytics.trend(days((0..<60).map { 100 + Double($0) * 2 }), days: 14)
        #expect(line.fit! > 0.999)
        #expect(abs(line.points.last!.value - (218 + 28)) < 0.01)
    }

    @Test func trendNeedsTwoWeeks() {
        #expect(Analytics.trend(days([1, 2, 3]), days: 14).points.isEmpty)
    }

    @Test func forecastStopsAtZero() {
        let line = Analytics.trend(days((0..<30).map { 300 - Double($0) * 10 }), days: 90)
        #expect(line.points.allSatisfy { $0.value >= 0 })
    }

    @Test func anomalyFindsTheOutlierAndIgnoresNoise() {
        var values = (0..<40).map { 100 + Double($0 % 5) }
        values[35] = 400
        let found = Analytics.anomalies(days(values))
        #expect(found.count == 1)
        #expect(found[0].value == 400)
    }

    @Test func weekdayIndexAveragesToOne() {
        let index = Analytics.weekdayIndex(days((0..<28).map { Double($0 % 7 + 1) }))
        #expect(index.count == 7)
        #expect(abs(index.reduce(0, +) / 7 - 1) < 0.0001)
    }

    @Test func churnBecomesLifetimeAndLTV() {
        let weekly = days([Double](repeating: 1, count: 8))
        let insights = Analytics.insights(overview: overview, revenueDaily: [], mrrDaily: [], movement: [], churnWeekly: weekly, trialsWeekly: [], countries: [], refundRate: nil, now: .now)
        #expect(abs(insights.monthlyChurn! - 0.0427) < 0.001)
        #expect(insights.arpu == 10)
        #expect(abs(insights.impliedLTV! - 10 / insights.monthlyChurn!) < 0.001)
    }

    @Test func quickRatioIsWonOverLost() {
        let weeks = (0..<8).map { MovementWeek(date: Date(timeIntervalSince1970: Double($0) * 7 * day), gained: 40, lost: 10) }
        let insights = Analytics.insights(overview: overview, revenueDaily: [], mrrDaily: [], movement: weeks, churnWeekly: [], trialsWeekly: [], countries: [], refundRate: nil, now: .now)
        #expect(insights.quickRatio == 4)
    }

    @Test func trialConversionCountsOnlyEndedTrials() {
        let weeks = [TrialWeek(date: .now, starts: 100, conversions: 30, completed: 60)]
        let insights = Analytics.insights(overview: overview, revenueDaily: [], mrrDaily: [], movement: [], churnWeekly: [], trialsWeekly: weeks, countries: [], refundRate: nil, now: .now)
        #expect(insights.trialConversion == 0.5)
        #expect(insights.trialPipelineMRR == 100)
    }

    @Test func noSubscribersMeansNoDivisionByZero() {
        var empty = overview
        empty.activeSubscriptions = 0
        empty.mrr = 0
        let insights = Analytics.insights(overview: empty, revenueDaily: [], mrrDaily: [], movement: [], churnWeekly: [], trialsWeekly: [], countries: [], refundRate: nil, now: .now)
        #expect(insights.arpu == nil && insights.impliedLTV == nil)
    }

    @Test func portfolioNeverAddsCurrencies() {
        var euro = overview
        euro.currency = "EUR"
        let a = ProjectReport(project: RCProject(id: "a", name: "A"), overview: overview, updatedAt: .now)
        let b = ProjectReport(project: RCProject(id: "b", name: "B"), overview: euro, updatedAt: .now)
        let c = ProjectReport(project: RCProject(id: "c", name: "C"), overview: overview, updatedAt: .now)
        let portfolio = Analytics.portfolio([a, b, c])
        #expect(portfolio.totals.map(\.currency) == ["EUR", "USD"])
        #expect(portfolio.totals[1].mrr == 2000)
    }
}

@Suite struct ChartTests {
    private func chart(_ json: String) throws -> Chart {
        try JSONDecoder().decode(Chart.self, from: Data(json.utf8))
    }

    @Test func readsTheRealShapes() throws {
        let c = try chart(#"{"measures":[{"display_name":"Revenue"},{"display_name":"Transactions"}],"values":[{"cohort":2,"value":5.5,"measure":0,"incomplete":false},{"cohort":1,"value":3,"measure":0,"incomplete":false},{"cohort":1,"value":9,"measure":1,"incomplete":true}],"yaxis_currency":"EUR"}"#)
        #expect(c.series("Revenue").map(\.value) == [3, 5.5])
        #expect(c.series("Transactions").first?.incomplete == true)
        #expect(c.series("Nothing").isEmpty)
        #expect(c.currency == "EUR")
    }

    @Test func nullValuesDoNotBreakDecoding() throws {
        let c = try chart(#"{"measures":null,"values":[{"cohort":1,"value":null,"measure":0}]}"#)
        #expect(c.values[0].value == 0)
    }

    @Test func retentionUsesRateColumnsAndSkipsTheTotalRow() throws {
        let c = try chart(#"{"periods":[{"display_name":"Subscriptions"},{"display_name":"Month 1","scale":"absolute"},{"display_name":"Month 1 rate","scale":"relative"}],"values":[{"cohort":"Total","period":0,"value":99},{"cohort":100,"period":0,"value":50},{"cohort":100,"period":1,"value":40},{"cohort":100,"period":2,"value":80.0}]}"#)
        let rows = c.retentionRows()
        #expect(rows.count == 1)
        #expect(rows[0].size == 50)
        #expect(rows[0].cells == [0.8])
    }

    @Test func sharesLeaveOutTheTotalSegment() throws {
        let c = try chart(#"{"segments":[{"display_name":"Total","is_total":true},{"display_name":"US","is_total":false},{"display_name":"DE","is_total":false}],"values":[{"cohort":1,"value":100,"measure":0,"segment":0},{"cohort":1,"value":75,"measure":0,"segment":1},{"cohort":1,"value":25,"measure":0,"segment":2}]}"#)
        #expect(c.shares().map(\.name) == ["US", "DE"])
        #expect(c.shares()[0].fraction == 0.75)
    }
}

@Suite struct AlertTests {
    private func report(mrr: Double = 1000, subs: Double = 100) -> ProjectReport {
        var o = overview
        o.mrr = mrr
        o.activeSubscriptions = subs
        return ProjectReport(project: RCProject(id: "p", name: "P"), overview: o, updatedAt: .now)
    }

    @Test func newSubscribersAndMilestone() {
        let alerts = AlertRulesEngine.alerts(previous: report(mrr: 990, subs: 98), current: report(mrr: 1010, subs: 100), rules: .standard, now: .now)
        #expect(alerts.map(\.kind).contains(.newSubscribers))
        #expect(alerts.first { $0.kind == .mrrMilestone }?.value == 1000)
    }

    @Test func firstRunRaisesNothing() {
        #expect(AlertRulesEngine.alerts(previous: nil, current: report(), rules: .standard, now: .now).isEmpty)
    }

    @Test func mrrDropRespectsThresholdAndSwitch() {
        var current = report()
        current.mrrDaily = days([1000, 1000, 1000, 1000, 1000, 1000, 1000, 900])
        #expect(AlertRulesEngine.alerts(previous: nil, current: current, rules: .standard, now: .now).map(\.kind) == [.mrrDrop])
        var off = AlertRules.standard
        off.enabled[.mrrDrop] = false
        #expect(AlertRulesEngine.alerts(previous: nil, current: current, rules: off, now: .now).isEmpty)
    }

    @Test func churnSpikeComparesWithTheWeeksBefore() {
        var current = report()
        current.churnWeekly = days([1, 1, 1, 1, 1, 1, 1, 1, 2])
        #expect(AlertRulesEngine.alerts(previous: nil, current: current, rules: .standard, now: .now).map(\.kind) == [.churnSpike])
    }
}

@Suite struct EngineTests {
    @Test func demoRunsThroughTheWholePipeline() async throws {
        let engine = Engine(source: DemoSource(), spacing: .nanoseconds(1), persists: false)
        await engine.refresh()
        let portfolio = await engine.portfolio()
        #expect(portfolio.reports.count == 4)
        #expect(portfolio.totals.count == 1)
        let report = try #require(await engine.report("demo_pulse"))
        #expect(report.revenueDaily.count == 400)
        #expect(report.movement.count == 26)
        #expect(!report.retention.isEmpty)
        #expect(report.countries.first?.name == "United States")
        #expect(report.insights.quickRatio != nil)
        #expect(report.insights.forecast.count > 2)
        #expect(report.chartsUpdatedAt != nil)
    }

    @Test func checksumIsFoundByFileName() {
        let text = "abc123  rc_0.1.7_darwin_amd64.tar.gz\nDEF456  rc_0.1.7_darwin_arm64.tar.gz\n"
        #expect(ToolInstaller.expectedChecksum(in: text, for: "rc_0.1.7_darwin_arm64.tar.gz") == "def456")
        #expect(ToolInstaller.expectedChecksum(in: text, for: "missing") == nil)
    }

    @Test func requestParsingWaitsForTheBody() {
        let head = "POST /v1/refresh HTTP/1.1\r\nAuthorization: Bearer x\r\nContent-Length: 2\r\n\r\n"
        #expect(Hub.parse(Data((head + "{").utf8)) == nil)
        let request = Hub.parse(Data((head + "{}").utf8))
        #expect(request?.path == "/v1/refresh")
        #expect(request?.authorization == "Bearer x")
    }

    @Test func expiredLoginIsSignedOut() {
        let failure = ProcessResult(code: 1, stdout: Data(), stderr: "Error: not logged in, run rc auth login")
        #expect(RevenueCatCLI.error(from: failure) == .signedOut)
        let limit = ProcessResult(code: 1, stdout: Data(#"{"error":{"message":"HTTP 429"}}"#.utf8), stderr: "")
        #expect(RevenueCatCLI.error(from: limit) == .rateLimited)
    }
}
