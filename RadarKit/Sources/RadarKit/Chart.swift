import Foundation

/// One answer of `GET /projects/{id}/charts/{name}`.
public struct Chart: Decodable, Sendable {
    public struct Measure: Decodable, Sendable {
        public var name: String
        enum CodingKeys: String, CodingKey { case name = "display_name" }
    }
    public struct Segment: Decodable, Sendable {
        public var name: String
        public var isTotal: Bool
        enum CodingKeys: String, CodingKey {
            case name = "display_name"
            case isTotal = "is_total"
        }
    }
    public struct Period: Decodable, Sendable {
        public var name: String
        public var scale: String?
        enum CodingKeys: String, CodingKey {
            case scale
            case name = "display_name"
        }
    }
    public struct Point: Decodable, Sendable {
        /// Seconds since 1970; nil on the "Total" row of a retention table.
        public var date: Date?
        public var value: Double
        public var measure: Int
        public var segment: Int
        public var period: Int
        public var incomplete: Bool

        enum CodingKeys: String, CodingKey { case cohort, value, measure, segment, period, incomplete }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            date = (try? c.decode(Double.self, forKey: .cohort)).map { Date(timeIntervalSince1970: $0) }
            value = (try? c.decodeIfPresent(Double.self, forKey: .value)) ?? 0
            measure = (try? c.decodeIfPresent(Int.self, forKey: .measure)) ?? 0
            segment = (try? c.decodeIfPresent(Int.self, forKey: .segment)) ?? 0
            period = (try? c.decodeIfPresent(Int.self, forKey: .period)) ?? 0
            incomplete = (try? c.decodeIfPresent(Bool.self, forKey: .incomplete)) ?? false
        }
    }

    public var measures: [Measure]?
    public var segments: [Segment]?
    public var periods: [Period]?
    public var values: [Point]
    public var currency: String?

    enum CodingKeys: String, CodingKey {
        case measures, segments, periods, values
        case currency = "yaxis_currency"
    }

    public func measureIndex(_ name: String) -> Int? {
        measures?.firstIndex { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// The dated values of one measure, oldest first. Without a name, the first measure.
    public func series(_ measure: String? = nil, segment: Int = 0) -> [Chart.Point] {
        let index = measure.flatMap(measureIndex) ?? 0
        if measure != nil, measureIndex(measure!) == nil { return [] }
        return values.filter { $0.measure == index && $0.segment == segment && $0.date != nil }
            .sorted { $0.date! < $1.date! }
    }

    /// The largest segments by total, with their share of everything.
    public func shares(limit: Int = 6) -> [Share] {
        guard let segments else { return [] }
        var totals: [(name: String, value: Double)] = []
        for (index, segment) in segments.enumerated() where !segment.isTotal {
            let total = values.filter { $0.segment == index && $0.measure == 0 && !$0.incomplete }.reduce(0) { $0 + $1.value }
            if total > 0 { totals.append((segment.name.isEmpty ? "—" : segment.name, total)) }
        }
        let all = totals.reduce(0) { $0 + $1.value }
        guard all > 0 else { return [] }
        return totals.sorted { $0.value > $1.value }.prefix(limit).map { Share(name: $0.name, value: $0.value, fraction: $0.value / all) }
    }

    /// Cohorts by month. A cell is the share still subscribed, 0…1.
    public func retentionRows(limit: Int = 12) -> [RetentionRow] {
        guard let periods else { return [] }
        let rateColumns = periods.indices.filter { periods[$0].scale == "relative" }
        let byDate = Dictionary(grouping: values.filter { $0.date != nil }) { $0.date! }
        return byDate.keys.sorted().suffix(limit).map { date in
            let row = byDate[date]!
            let cells = rateColumns.map { column -> Double? in
                row.first { $0.period == column }.map { $0.value / 100 }
            }
            return RetentionRow(cohort: date, size: row.first { $0.period == 0 }?.value ?? 0, cells: cells)
        }
    }
}
