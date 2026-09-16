import Foundation
import SwiftData

/// 由采购需求派生的一条提醒，对应本地通知 / 系统日历 / 飞书日历中的一个或多个实体
@Model
final class ReminderEvent: Identifiable {
    var id: UUID

    /// 同一采购需求下同类型提醒的稳定标识（delivery-before / delivery-day / invoice / custom）
    var stableKey: String
    var kindRaw: String
    var fireDate: Date
    var title: String
    var bodyText: String

    /// 本地通知标识
    var localNotificationID: String?
    var localScheduled: Bool

    /// 飞书日程标识
    var feishuEventID: String?
    var feishuSynced: Bool

    /// 系统日历事件标识
    var systemEventID: String?
    var systemSynced: Bool

    var lastError: String?
    var updatedAt: Date

    var item: PurchaseItem?

    init(
        id: UUID = UUID(),
        stableKey: String,
        kind: ReminderKind,
        fireDate: Date,
        title: String,
        bodyText: String
    ) {
        self.id = id
        self.stableKey = stableKey
        self.kindRaw = kind.rawValue
        self.fireDate = fireDate
        self.title = title
        self.bodyText = bodyText
        self.localScheduled = false
        self.feishuSynced = false
        self.systemSynced = false
        self.updatedAt = Date()
    }

    var kind: ReminderKind {
        get { ReminderKind(rawValue: kindRaw) ?? .custom }
        set { kindRaw = newValue.rawValue }
    }
}
