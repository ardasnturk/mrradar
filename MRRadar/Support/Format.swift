import Foundation
import RadarKit

extension RCProject: RCProjectLike {}

enum Format {
    static func money(_ value: Double, _ currency: String, compact: Bool = false) -> String {
        if compact, abs(value) >= 10_000 {
            let number = value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
            let symbol = Locale.current.localizedCurrencySymbol(currency)
            return "\(symbol)\(number)"
        }
        return value.formatted(.currency(code: currency).precision(.fractionLength(abs(value) >= 1000 ? 0 : 2)))
    }

    static func count(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    static func percent(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.percent.precision(.fractionLength(0...digits)))
    }

    static func signedPercent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0...1)).sign(strategy: .always(includingZero: false)))
    }

    static func ratio(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1))))×"
    }

    static func months(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

extension Locale {
    func localizedCurrencySymbol(_ code: String) -> String {
        Locale(identifier: "\(identifier)@currency=\(code)").currencySymbol ?? code
    }
}
