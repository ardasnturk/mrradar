import AppKit
import RadarKit
import UserNotifications

/// Texts of an alert, here so the Mac notification and the list in the app read the same.
extension RadarAlert {
    var title: String {
        switch kind {
        case .newSubscribers: String(localized: "New subscribers · \(projectName)")
        case .mrrDrop: String(localized: "MRR is falling · \(projectName)")
        case .mrrMilestone: String(localized: "MRR milestone · \(projectName)")
        case .revenueSpike: String(localized: "Unusually good day · \(projectName)")
        case .revenueDip: String(localized: "Unusually quiet day · \(projectName)")
        case .refundSpike: String(localized: "Refunds are high · \(projectName)")
        case .churnSpike: String(localized: "Churn is up · \(projectName)")
        }
    }

    var body: String {
        let amount = currency.map { Format.money(value, $0) } ?? Format.count(value)
        let share = fraction.map { Format.percent($0) } ?? ""
        switch kind {
        case .newSubscribers: return String(localized: "\(amount) more active subscribers.")
        case .mrrDrop: return String(localized: "Down \(share) in 7 days (\(amount)).")
        case .mrrMilestone: return String(localized: "MRR passed \(amount).")
        case .revenueSpike, .revenueDip: return String(localized: "\(amount), \(share) away from a normal day.")
        case .refundSpike: return String(localized: "\(Format.percent(value)) of last month's transactions were refunded.")
        case .churnSpike: return String(localized: "\(Format.percent(value)) of subscribers left this week, \(share) above normal.")
        }
    }

    var symbol: String {
        switch kind {
        case .newSubscribers: "person.badge.plus"
        case .mrrDrop: "chart.line.downtrend.xyaxis"
        case .mrrMilestone: "flag.checkered"
        case .revenueSpike: "arrow.up.right"
        case .revenueDip: "arrow.down.right"
        case .refundSpike: "arrow.uturn.left"
        case .churnSpike: "person.badge.minus"
        }
    }

    var isGood: Bool { kind == .newSubscribers || kind == .mrrMilestone || kind == .revenueSpike }
}

@MainActor
enum Notifier {
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func isAllowed() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized
    }

    static func post(_ alert: RadarAlert) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        content.userInfo = ["project": alert.projectID]
        let request = UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Shows banners while MRRadar is in front, and opens the project a notification is about.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    let open: @MainActor @Sendable (String) -> Void

    init(open: @escaping @MainActor @Sendable (String) -> Void) {
        self.open = open
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let project = response.notification.request.content.userInfo["project"] as? String else { return }
        await open(project)
    }
}
