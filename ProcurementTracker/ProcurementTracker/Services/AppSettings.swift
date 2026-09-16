import Foundation
import Observation

/// 应用设置（UserDefaults 保存普通配置，App Secret / Token 走钥匙串）
@Observable
final class AppSettings {
    private let defaults = UserDefaults.standard

    // MARK: - 飞书应用配置
    var feishuDomainRaw: String {
        didSet { defaults.set(feishuDomainRaw, forKey: Keys.domain) }
    }

    var feishuAppID: String {
        didSet { defaults.set(feishuAppID, forKey: Keys.appID) }
    }

    var redirectURI: String {
        didSet { defaults.set(redirectURI, forKey: Keys.redirectURI) }
    }

    /// App Secret 保存在钥匙串中
    var feishuAppSecret: String {
        get {
            guard let data = KeychainHelper.get(KeychainHelper.Key.feishuSecret),
                  let value = String(data: data, encoding: .utf8) else { return "" }
            return value
        }
        set {
            if newValue.isEmpty {
                KeychainHelper.delete(KeychainHelper.Key.feishuSecret)
            } else {
                KeychainHelper.set(Data(newValue.utf8), for: KeychainHelper.Key.feishuSecret)
            }
        }
    }

    var feishuCalendarID: String {
        didSet { defaults.set(feishuCalendarID, forKey: Keys.calendarID) }
    }

    var feishuUserName: String {
        didSet { defaults.set(feishuUserName, forKey: Keys.userName) }
    }

    // MARK: - 渠道默认开关
    var defaultLocalEnabled: Bool {
        didSet { defaults.set(defaultLocalEnabled, forKey: Keys.defaultLocal) }
    }

    var defaultFeishuEnabled: Bool {
        didSet { defaults.set(defaultFeishuEnabled, forKey: Keys.defaultFeishu) }
    }

    var defaultSystemCalendarEnabled: Bool {
        didSet { defaults.set(defaultSystemCalendarEnabled, forKey: Keys.defaultSystemCalendar) }
    }

    // MARK: - 默认提醒规则
    var defaultDeliveryDaysBefore: Int {
        didSet { defaults.set(defaultDeliveryDaysBefore, forKey: Keys.deliveryDaysBefore) }
    }

    var defaultInvoiceDaysAfter: Int {
        didSet { defaults.set(defaultInvoiceDaysAfter, forKey: Keys.invoiceDaysAfter) }
    }

    var defaultReminderHour: Int {
        didSet { defaults.set(defaultReminderHour, forKey: Keys.reminderHour) }
    }

    var timezoneIdentifier: String {
        didSet { defaults.set(timezoneIdentifier, forKey: Keys.timezone) }
    }

    init() {
        let d = UserDefaults.standard
        self.feishuDomainRaw = d.string(forKey: Keys.domain) ?? FeishuDomain.feishuCN.rawValue
        self.feishuAppID = d.string(forKey: Keys.appID) ?? ""
        self.redirectURI = d.string(forKey: Keys.redirectURI) ?? "procurement-tracker://oauth/callback"
        self.feishuCalendarID = d.string(forKey: Keys.calendarID) ?? ""
        self.feishuUserName = d.string(forKey: Keys.userName) ?? ""
        self.defaultLocalEnabled = d.object(forKey: Keys.defaultLocal) as? Bool ?? true
        self.defaultFeishuEnabled = d.object(forKey: Keys.defaultFeishu) as? Bool ?? false
        self.defaultSystemCalendarEnabled = d.object(forKey: Keys.defaultSystemCalendar) as? Bool ?? false
        self.defaultDeliveryDaysBefore = d.object(forKey: Keys.deliveryDaysBefore) as? Int ?? 3
        self.defaultInvoiceDaysAfter = d.object(forKey: Keys.invoiceDaysAfter) as? Int ?? 7
        self.defaultReminderHour = d.object(forKey: Keys.reminderHour) as? Int ?? 9
        self.timezoneIdentifier = d.string(forKey: Keys.timezone) ?? TimeZone.current.identifier
    }

    var domain: FeishuDomain {
        FeishuDomain(rawValue: feishuDomainRaw) ?? .feishuCN
    }

    /// 新建采购需求时套用默认提醒设置
    func applyDefaults(to item: PurchaseItem) {
        item.notifyLocal = defaultLocalEnabled
        item.syncFeishu = defaultFeishuEnabled
        item.syncSystemCalendar = defaultSystemCalendarEnabled
        item.deliveryReminderDaysBefore = defaultDeliveryDaysBefore
        item.invoiceReminderDaysAfter = defaultInvoiceDaysAfter
    }

    private enum Keys {
        static let domain = "feishu.domain"
        static let appID = "feishu.appID"
        static let redirectURI = "feishu.redirectURI"
        static let calendarID = "feishu.calendarID"
        static let userName = "feishu.userName"
        static let defaultLocal = "reminder.defaultLocal"
        static let defaultFeishu = "reminder.defaultFeishu"
        static let defaultSystemCalendar = "reminder.defaultSystemCalendar"
        static let deliveryDaysBefore = "reminder.deliveryDaysBefore"
        static let invoiceDaysAfter = "reminder.invoiceDaysAfter"
        static let reminderHour = "reminder.hour"
        static let timezone = "reminder.timezone"
    }
}
