import Foundation
import EventKit

/// 系统日历渠道（写入 iPhone / Mac 自带“日历”App，通过 iCloud 在设备间同步）
@MainActor
final class SystemCalendarService {
    private let store = EKEventStore()
    private var accessGranted = false

    /// 请求日历写入权限（iOS 17 / macOS 14 的仅写入授权）
    func requestWriteAccess() async throws {
        if accessGranted { return }
        let granted = try await store.requestWriteOnlyAccessToEvents()
        accessGranted = granted
        if !granted { throw CalendarError.notAuthorized }
    }

    /// 创建一条 30 分钟的日历事件，提前 30 分钟弹窗提醒，返回事件标识
    @discardableResult
    func createEvent(title: String, notes: String, date: Date) async throws -> String {
        try await requestWriteAccess()
        guard let calendar = store.defaultCalendarForNewEvents else {
            throw CalendarError.noDefaultCalendar
        }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.notes = notes
        event.calendar = calendar
        event.startDate = date
        event.endDate = date.addingTimeInterval(30 * 60)
        event.addAlarm(EKAlarm(relativeOffset: -30 * 60))

        try store.save(event, span: .thisEvent)
        guard let identifier = event.eventIdentifier else {
            throw CalendarError.saveFailed
        }
        return identifier
    }

    /// 删除此前创建的事件；事件不存在时视为成功
    func removeEvent(identifier: String) async throws {
        try await requestWriteAccess()
        guard let event = store.event(withIdentifier: identifier) else { return }
        try store.remove(event, span: .thisEvent)
    }

    enum CalendarError: LocalizedError {
        case notAuthorized
        case noDefaultCalendar
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "系统日历写入权限未开启，请在系统设置中允许访问日历。"
            case .noDefaultCalendar:
                return "未找到可写入的默认日历，请在系统日历 App 中确认。"
            case .saveFailed:
                return "日历事件保存失败，请重试。"
            }
        }
    }
}
