import Foundation
import SwiftData
import UniformTypeIdentifiers

/// 采购需求 JSON 备份文件
struct BackupFile: Codable {
    let exportedAt: Date
    let appVersion: String
    var items: [ItemDTO]
}

/// 采购需求的数据传输对象
struct ItemDTO: Codable {
    var title: String
    var supplier: String
    var contact: String
    var quantity: Double
    var unit: String
    var unitPrice: Double
    var currency: String
    var orderDate: Date?
    var expectedDeliveryDate: Date?
    var actualDeliveryDate: Date?
    var deliveryStatusRaw: String
    var invoiceStatusRaw: String
    var paymentStatusRaw: String
    var completed: Bool
    var notes: String
    var deliveryReminderEnabled: Bool
    var deliveryReminderDaysBefore: Int
    var invoiceReminderEnabled: Bool
    var invoiceReminderDaysAfter: Int
    var customReminderEnabled: Bool
    var customReminderDate: Date?
    var notifyLocal: Bool
    var syncFeishu: Bool
    var syncSystemCalendar: Bool
    var createdAt: Date
    var updatedAt: Date

    init(from item: PurchaseItem) {
        self.title = item.title
        self.supplier = item.supplier
        self.contact = item.contact
        self.quantity = item.quantity
        self.unit = item.unit
        self.unitPrice = item.unitPrice
        self.currency = item.currency
        self.orderDate = item.orderDate
        self.expectedDeliveryDate = item.expectedDeliveryDate
        self.actualDeliveryDate = item.actualDeliveryDate
        self.deliveryStatusRaw = item.deliveryStatusRaw
        self.invoiceStatusRaw = item.invoiceStatusRaw
        self.paymentStatusRaw = item.paymentStatusRaw
        self.completed = item.completed
        self.notes = item.notes
        self.deliveryReminderEnabled = item.deliveryReminderEnabled
        self.deliveryReminderDaysBefore = item.deliveryReminderDaysBefore
        self.invoiceReminderEnabled = item.invoiceReminderEnabled
        self.invoiceReminderDaysAfter = item.invoiceReminderDaysAfter
        self.customReminderEnabled = item.customReminderEnabled
        self.customReminderDate = item.customReminderDate
        self.notifyLocal = item.notifyLocal
        self.syncFeishu = item.syncFeishu
        self.syncSystemCalendar = item.syncSystemCalendar
        self.createdAt = item.createdAt
        self.updatedAt = item.updatedAt
    }

    /// 转为可入库的采购需求（使用新的 UUID，避免与现有数据冲突）
    func toPurchaseItem() -> PurchaseItem {
        let item = PurchaseItem(
            title: title,
            supplier: supplier,
            contact: contact,
            quantity: quantity,
            unit: unit,
            unitPrice: unitPrice,
            currency: currency,
            orderDate: orderDate,
            notes: notes,
            expectedDeliveryDate: expectedDeliveryDate,
            actualDeliveryDate: actualDeliveryDate,
            deliveryStatus: DeliveryStatus(rawValue: deliveryStatusRaw) ?? .pending,
            invoiceStatus: InvoiceStatus(rawValue: invoiceStatusRaw) ?? .notIssued,
            paymentStatus: PaymentStatus(rawValue: paymentStatusRaw) ?? .unpaid,
            completed: completed,
            deliveryReminderEnabled: deliveryReminderEnabled,
            deliveryReminderDaysBefore: deliveryReminderDaysBefore,
            invoiceReminderEnabled: invoiceReminderEnabled,
            invoiceReminderDaysAfter: invoiceReminderDaysAfter,
            customReminderEnabled: customReminderEnabled,
            customReminderDate: customReminderDate,
            notifyLocal: notifyLocal,
            syncFeishu: syncFeishu,
            syncSystemCalendar: syncSystemCalendar
        )
        item.createdAt = createdAt
        item.updatedAt = updatedAt
        return item
    }
}

enum BackupService {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func exportData(items: [PurchaseItem]) throws -> Data {
        let file = BackupFile(
            exportedAt: Date(),
            appVersion: "1.0",
            items: items.map(ItemDTO.init)
        )
        return try encoder.encode(file)
    }

    /// 导入数据并写入数据库，返回新建的采购需求数量
    @discardableResult
    static func importData(_ data: Data, into context: ModelContext) throws -> Int {
        let file = try decoder.decode(BackupFile.self, from: data)
        for dto in file.items {
            let item = dto.toPurchaseItem()
            context.insert(item)
        }
        try context.save()
        return file.items.count
    }
}

/// 供 SwiftUI .fileExporter 使用的 JSON 文档
struct JSONBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileContents: data)
    }
}
