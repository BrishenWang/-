import Foundation

/// 到货状态
enum DeliveryStatus: String, Codable, CaseIterable, Identifiable {
    case pending = "未发货"
    case partial = "部分到货"
    case arrived = "已到货"

    var id: String { rawValue }
    var label: String { rawValue }
}

/// 发票状态
enum InvoiceStatus: String, Codable, CaseIterable, Identifiable {
    case notIssued = "未开票"
    case urged = "已催票"
    case issued = "已开票"

    var id: String { rawValue }
    var label: String { rawValue }
}

/// 付款状态
enum PaymentStatus: String, Codable, CaseIterable, Identifiable {
    case unpaid = "未付款"
    case partial = "部分付款"
    case paid = "已付款"

    var id: String { rawValue }
    var label: String { rawValue }
}

/// 提醒类型
enum ReminderKind: String, Codable, CaseIterable {
    case deliveryBefore = "delivery-before"
    case deliveryDay = "delivery-day"
    case invoice = "invoice"
    case custom = "custom"

    var label: String {
        switch self {
        case .deliveryBefore: return "到货预告"
        case .deliveryDay: return "大货到货"
        case .invoice: return "催开发票"
        case .custom: return "自定义提醒"
        }
    }

    var sfSymbol: String {
        switch self {
        case .deliveryBefore: return "shippingbox"
        case .deliveryDay: return "truck.box"
        case .invoice: return "doc.text.magnifyingglass"
        case .custom: return "bell"
        }
    }
}

/// 飞书站点（国内版 / 国际版 Lark）
enum FeishuDomain: String, Codable, CaseIterable, Identifiable {
    case feishuCN = "feishu"
    case larkGlobal = "lark"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .feishuCN: return "飞书（国内版）"
        case .larkGlobal: return "Lark（国际版）"
        }
    }

    var accountsHost: String {
        switch self {
        case .feishuCN: return "https://accounts.feishu.cn"
        case .larkGlobal: return "https://accounts.larksuite.com"
        }
    }

    var openAPIBaseURL: String {
        switch self {
        case .feishuCN: return "https://open.feishu.cn/open-apis"
        case .larkGlobal: return "https://open.larksuite.com/open-apis"
        }
    }
}
