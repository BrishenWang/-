import Foundation
import UserNotifications

/// 本地通知渠道（无需网络，离线也能提醒）
@MainActor
final class NotificationService {
    private let center = UNUserNotificationCenter.current()
    private(set) var authorizationChecked = false

    /// 请求通知授权（已授权时直接返回）
    @discardableResult
    func requestAuthorization() async throws -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            authorizationChecked = true
            return true
        case .denied:
            authorizationChecked = true
            return false
        default:
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            authorizationChecked = true
            return granted
        }
    }

    /// 安排一条本地通知
    func schedule(identifier: String, title: String, body: String, date: Date) async throws {
        let granted = try await requestAuthorization()
        guard granted else { throw NotificationError.notAuthorized }

        cancel(identifiers: [identifier])

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        try await center.add(request)
    }

    func cancel(identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func pendingIdentifiers() async -> Set<String> {
        let requests = await center.pendingNotificationRequests()
        return Set(requests.map(\.identifier))
    }

    enum NotificationError: LocalizedError {
        case notAuthorized
        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "系统通知权限未开启，请在系统设置中允许通知。"
            }
        }
    }
}
