import Foundation
import Observation
import SwiftData

/// 提醒调度引擎：根据采购需求的规则生成提醒，并同步到本地通知 / 系统日历 / 飞书日历
@MainActor
@Observable
final class ReminderScheduler {
    let settings: AppSettings
    let feishu: FeishuClient
    let notifications: NotificationService
    let systemCalendar: SystemCalendarService

    var isSyncing = false
    var lastMessage: String?

    /// 一条期望存在的提醒（由采购规则计算得出）
    struct Blueprint: Identifiable, Equatable {
        let stableKey: String
        let kind: ReminderKind
        let date: Date
        let title: String
        let body: String
        var id: String { stableKey }
    }

    init(settings: AppSettings, feishu: FeishuClient, notifications: NotificationService, systemCalendar: SystemCalendarService) {
        self.settings = settings
        self.feishu = feishu
        self.notifications = notifications
        self.systemCalendar = systemCalendar
    }

    // MARK: - 对外方法

    /// 根据采购需求当前状态，增删改对应的全部提醒
    func reconcile(item: PurchaseItem, in context: ModelContext) async {
        let blueprints = Self.blueprints(for: item, settings: settings)

        var existing = [String: ReminderEvent]()
        for reminder in item.reminders {
            existing[reminder.stableKey] = reminder
        }

        var validKeys = Set<String>()
        for blueprint in blueprints {
            validKeys.insert(blueprint.stableKey)
            let reminder: ReminderEvent
            if let found = existing[blueprint.stableKey] {
                reminder = found
            } else {
                reminder = ReminderEvent(
                    stableKey: blueprint.stableKey,
                    kind: blueprint.kind,
                    fireDate: blueprint.date,
                    title: blueprint.title,
                    bodyText: blueprint.body
                )
                reminder.item = item
                context.insert(reminder)
            }
            await applyChannels(item: item, reminder: reminder, blueprint: blueprint)
        }

        let staleReminders = item.reminders.filter { !validKeys.contains($0.stableKey) }
        for reminder in staleReminders {
            await revokeChannels(reminder)
            context.delete(reminder)
        }

        item.updatedAt = Date()
        try? context.save()
    }

    /// 对所有未完成采购需求重新同步（例如飞书登录成功后）
    func reconcileAll(in context: ModelContext) async {
        isSyncing = true
        defer { isSyncing = false }
        let descriptor = FetchDescriptor<PurchaseItem>(predicate: #Predicate<PurchaseItem> { !$0.completed })
        let items = (try? context.fetch(descriptor)) ?? []
        for item in items {
            await reconcile(item: item, in: context)
        }
        lastMessage = "已同步 \(items.count) 条采购需求的提醒。"
    }

    /// 删除采购需求前，撤销其在各渠道的外部实体
    func teardown(item: PurchaseItem, in context: ModelContext) async {
        for reminder in item.reminders {
            await revokeChannels(reminder)
        }
        context.delete(item)
        try? context.save()
    }

    // MARK: - 渠道同步

    private func applyChannels(item: PurchaseItem, reminder: ReminderEvent, blueprint: Blueprint) async {
        let contentChanged = reminder.fireDate != blueprint.date
            || reminder.title != blueprint.title
            || reminder.bodyText != blueprint.body

        reminder.kind = blueprint.kind
        reminder.fireDate = blueprint.date
        reminder.title = blueprint.title
        reminder.bodyText = blueprint.body
        reminder.updatedAt = Date()

        var errors: [String] = []

        // 1) 本地通知
        if item.notifyLocal {
            if !reminder.localScheduled || contentChanged || reminder.localNotificationID == nil {
                await revokeLocal(reminder)
                let identifier = reminder.id.uuidString
                do {
                    try await notifications.schedule(
                        identifier: identifier,
                        title: blueprint.title,
                        body: blueprint.body,
                        date: blueprint.date
                    )
                    reminder.localNotificationID = identifier
                    reminder.localScheduled = true
                } catch {
                    reminder.localScheduled = false
                    errors.append("本地通知：\(error.localizedDescription)")
                }
            }
        } else if reminder.localScheduled {
            await revokeLocal(reminder)
        }

        // 2) 飞书日历
        if item.syncFeishu {
            if feishu.isLoggedIn {
                if !reminder.feishuSynced || contentChanged || reminder.feishuEventID == nil {
                    await revokeFeishu(reminder)
                    do {
                        let eventID = try await feishu.createReminderEvent(
                            title: blueprint.title,
                            description: Self.eventDescription(item: item, body: blueprint.body),
                            date: blueprint.date,
                            idempotencyKey: "\(reminder.id.uuidString)-\(Int(reminder.updatedAt.timeIntervalSince1970))"
                        )
                        reminder.feishuEventID = eventID
                        reminder.feishuSynced = true
                    } catch {
                        reminder.feishuSynced = false
                        errors.append("飞书日历：\(error.localizedDescription)")
                    }
                }
            } else {
                reminder.feishuSynced = false
                if reminder.feishuEventID == nil {
                    errors.append("飞书日历：尚未登录授权")
                }
            }
        } else if reminder.feishuSynced {
            await revokeFeishu(reminder)
        }

        // 3) 系统日历
        if item.syncSystemCalendar {
            if !reminder.systemSynced || contentChanged || reminder.systemEventID == nil {
                await revokeSystem(reminder)
                do {
                    let identifier = try await systemCalendar.createEvent(
                        title: blueprint.title,
                        notes: Self.eventDescription(item: item, body: blueprint.body),
                        date: blueprint.date
                    )
                    reminder.systemEventID = identifier
                    reminder.systemSynced = true
                } catch {
                    reminder.systemSynced = false
                    errors.append("系统日历：\(error.localizedDescription)")
                }
            }
        } else if reminder.systemSynced {
            await revokeSystem(reminder)
        }

        let existingError = reminder.lastError
        reminder.lastError = errors.isEmpty ? nil : errors.joined(separator: "\n")
        if errors.isEmpty, existingError != nil {
            reminder.updatedAt = Date()
        }
    }

    private func revokeLocal(_ reminder: ReminderEvent) async {
        if let identifier = reminder.localNotificationID {
            notifications.cancel(identifiers: [identifier])
        }
        reminder.localNotificationID = nil
        reminder.localScheduled = false
    }

    private func revokeFeishu(_ reminder: ReminderEvent) async {
        if let eventID = reminder.feishuEventID {
            try? await feishu.deleteReminderEvent(eventID: eventID)
        }
        reminder.feishuEventID = nil
        reminder.feishuSynced = false
    }

    private func revokeSystem(_ reminder: ReminderEvent) async {
        if let eventID = reminder.systemEventID {
            try? await systemCalendar.removeEvent(identifier: eventID)
        }
        reminder.systemEventID = nil
        reminder.systemSynced = false
    }

    private func revokeChannels(_ reminder: ReminderEvent) async {
        await revokeLocal(reminder)
        await revokeFeishu(reminder)
        await revokeSystem(reminder)
    }

    // MARK: - 提醒规则计算

    static func blueprints(for item: PurchaseItem, settings: AppSettings, now: Date = Date()) -> [Blueprint] {
        guard !item.completed else { return [] }
        let calendar = Calendar.current
        var result: [Blueprint] = []

        func reminderTime(on date: Date) -> Date {
            let day = calendar.startOfDay(for: date)
            return calendar.date(
                bySettingHour: settings.defaultReminderHour,
                minute: 0,
                second: 0,
                of: day
            ) ?? day
        }

        // 若提醒时刻已过，顺延到明天的提醒时刻，保证用户一定能收到
        func ensureFuture(_ date: Date) -> Date {
            if date > now.addingTimeInterval(60) { return date }
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else {
                return date
            }
            return calendar.date(
                bySettingHour: settings.defaultReminderHour,
                minute: 0,
                second: 0,
                of: tomorrow
            ) ?? date
        }

        // 大货到货提醒
        if item.deliveryReminderEnabled,
           item.deliveryStatus != .arrived,
           let expected = item.expectedDeliveryDate {
            let daysBefore = max(item.deliveryReminderDaysBefore, 0)

            if daysBefore > 0,
               let beforeDate = calendar.date(byAdding: .day, value: -daysBefore, to: calendar.startOfDay(for: expected)) {
                result.append(Blueprint(
                    stableKey: ReminderKind.deliveryBefore.rawValue,
                    kind: .deliveryBefore,
                    date: ensureFuture(reminderTime(on: beforeDate)),
                    title: "到货预告：\(item.title) 还有 \(daysBefore) 天大货到达",
                    body: "向\(supplierText(item))采购的 \(quantityText(item))「\(item.title)」预计 \(dateText(expected)) 到达，请提前安排验收入库。"
                ))
            }

            result.append(Blueprint(
                stableKey: ReminderKind.deliveryDay.rawValue,
                kind: .deliveryDay,
                date: ensureFuture(reminderTime(on: expected)),
                title: "大货到货：\(item.title) 预计今日到达",
                body: "\(supplierText(item))的大货（\(quantityText(item))）预计今日到达，请安排验收，并跟进尾款与发票。"
            ))
        }

        // 催开发票提醒
        if item.invoiceReminderEnabled,
           item.invoiceStatus != .issued,
           let baseDate = item.deliveryReferenceDate {
            let daysAfter = max(item.invoiceReminderDaysAfter, 0)
            if let targetDate = calendar.date(byAdding: .day, value: daysAfter, to: calendar.startOfDay(for: baseDate)) {
                result.append(Blueprint(
                    stableKey: ReminderKind.invoice.rawValue,
                    kind: .invoice,
                    date: ensureFuture(reminderTime(on: targetDate)),
                    title: "催开发票：\(item.title) 的发票尚未开具",
                    body: "「\(item.title)」到货已 \(daysAfter) 天，\(supplierText(item))仍未开票（金额 \(moneyText(item.totalPrice, currency: item.currency))），请尽快催要发票。"
                ))
            }
        }

        // 自定义提醒
        if item.customReminderEnabled, let customDate = item.customReminderDate {
            result.append(Blueprint(
                stableKey: ReminderKind.custom.rawValue,
                kind: .custom,
                date: ensureFuture(customDate),
                title: "采购提醒：\(item.title)",
                body: item.notes.isEmpty ? "你设置了一条采购跟进提醒，请及时处理。" : item.notes
            ))
        }

        return result.sorted { $0.date < $1.date }
    }

    // MARK: - 文案辅助

    static func eventDescription(item: PurchaseItem, body: String) -> String {
        var lines = [body]
        if !item.supplier.isEmpty { lines.append("供应商：\(item.supplier)") }
        if !item.contact.isEmpty { lines.append("联系方式：\(item.contact)") }
        lines.append("数量：\(quantityText(item))")
        if item.unitPrice > 0 {
            lines.append("金额：\(moneyText(item.totalPrice, currency: item.currency))")
        }
        if !item.notes.isEmpty { lines.append("备注：\(item.notes)") }
        lines.append("——由采购管家 App 自动创建")
        return lines.joined(separator: "\n")
    }

    static func quantityText(_ item: PurchaseItem) -> String {
        let quantity: String = item.quantity == item.quantity.rounded()
            ? String(Int(item.quantity))
            : String(item.quantity)
        return "\(quantity)\(item.unit)"
    }

    static func supplierText(_ item: PurchaseItem) -> String {
        item.supplier.isEmpty ? "供应商" : item.supplier
    }

    static func moneyText(_ value: Double, currency: String) -> String {
        let symbol: String
        switch currency {
        case "CNY": symbol = "￥"
        case "USD": symbol = "$"
        case "EUR": symbol = "€"
        default: symbol = ""
        }
        return symbol + String(format: "%.2f", value)
    }

    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }
}
