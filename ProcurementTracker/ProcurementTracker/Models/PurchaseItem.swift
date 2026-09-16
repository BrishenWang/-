import Foundation
import SwiftData

/// 一条采购需求
@Model
final class PurchaseItem: Identifiable {
    /// 由代码生成的 UUID（不使用数据库唯一约束，以便将来开启 CloudKit 同步）
    var id: UUID

    // MARK: - 基本信息
    var title: String
    var supplier: String
    var contact: String
    var quantity: Double
    var unit: String
    var unitPrice: Double
    var currency: String
    var orderDate: Date?
    var notes: String

    // MARK: - 到货 / 发票 / 付款
    var expectedDeliveryDate: Date?
    var actualDeliveryDate: Date?
    var deliveryStatusRaw: String
    var invoiceStatusRaw: String
    var paymentStatusRaw: String
    var completed: Bool

    // MARK: - 提醒规则
    var deliveryReminderEnabled: Bool
    var deliveryReminderDaysBefore: Int
    var invoiceReminderEnabled: Bool
    var invoiceReminderDaysAfter: Int
    var customReminderEnabled: Bool
    var customReminderDate: Date?

    // MARK: - 提醒渠道
    var notifyLocal: Bool
    var syncFeishu: Bool
    var syncSystemCalendar: Bool

    // MARK: - 元数据
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ReminderEvent.item)
    var reminders: [ReminderEvent]

    init(
        id: UUID = UUID(),
        title: String = "",
        supplier: String = "",
        contact: String = "",
        quantity: Double = 1,
        unit: String = "件",
        unitPrice: Double = 0,
        currency: String = "CNY",
        orderDate: Date? = Calendar.current.startOfDay(for: Date()),
        notes: String = "",
        expectedDeliveryDate: Date? = nil,
        actualDeliveryDate: Date? = nil,
        deliveryStatus: DeliveryStatus = .pending,
        invoiceStatus: InvoiceStatus = .notIssued,
        paymentStatus: PaymentStatus = .unpaid,
        completed: Bool = false,
        deliveryReminderEnabled: Bool = true,
        deliveryReminderDaysBefore: Int = 3,
        invoiceReminderEnabled: Bool = true,
        invoiceReminderDaysAfter: Int = 7,
        customReminderEnabled: Bool = false,
        customReminderDate: Date? = nil,
        notifyLocal: Bool = true,
        syncFeishu: Bool = false,
        syncSystemCalendar: Bool = false
    ) {
        self.id = id
        self.title = title
        self.supplier = supplier
        self.contact = contact
        self.quantity = quantity
        self.unit = unit
        self.unitPrice = unitPrice
        self.currency = currency
        self.orderDate = orderDate
        self.notes = notes
        self.expectedDeliveryDate = expectedDeliveryDate
        self.actualDeliveryDate = actualDeliveryDate
        self.deliveryStatusRaw = deliveryStatus.rawValue
        self.invoiceStatusRaw = invoiceStatus.rawValue
        self.paymentStatusRaw = paymentStatus.rawValue
        self.completed = completed
        self.deliveryReminderEnabled = deliveryReminderEnabled
        self.deliveryReminderDaysBefore = deliveryReminderDaysBefore
        self.invoiceReminderEnabled = invoiceReminderEnabled
        self.invoiceReminderDaysAfter = invoiceReminderDaysAfter
        self.customReminderEnabled = customReminderEnabled
        self.customReminderDate = customReminderDate
        self.notifyLocal = notifyLocal
        self.syncFeishu = syncFeishu
        self.syncSystemCalendar = syncSystemCalendar
        self.createdAt = Date()
        self.updatedAt = Date()
        self.reminders = []
    }

    // MARK: - 枚举便捷访问
    var deliveryStatus: DeliveryStatus {
        get { DeliveryStatus(rawValue: deliveryStatusRaw) ?? .pending }
        set { deliveryStatusRaw = newValue.rawValue }
    }

    var invoiceStatus: InvoiceStatus {
        get { InvoiceStatus(rawValue: invoiceStatusRaw) ?? .notIssued }
        set { invoiceStatusRaw = newValue.rawValue }
    }

    var paymentStatus: PaymentStatus {
        get { PaymentStatus(rawValue: paymentStatusRaw) ?? .unpaid }
        set { paymentStatusRaw = newValue.rawValue }
    }

    var totalPrice: Double {
        quantity * unitPrice
    }

    /// 用于判断到货进度的基准日期（实际到货优先，否则预计到货）
    var deliveryReferenceDate: Date? {
        actualDeliveryDate ?? expectedDeliveryDate
    }
}
