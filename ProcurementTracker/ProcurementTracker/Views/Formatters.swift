import Foundation

/// 界面通用格式化工具
enum AppFormat {
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    static func day(_ date: Date?) -> String {
        guard let date else { return "未设置" }
        return dayFormatter.string(from: date)
    }

    static func dateTime(_ date: Date) -> String {
        dateTimeFormatter.string(from: date)
    }

    /// 相对今天的描述：今天 / 明天 / 后天 / N天后 / 逾期N天
    static func relativeDay(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.day], from: today, to: target)
        let days = components.day ?? 0
        switch days {
        case 0: return "今天"
        case 1: return "明天"
        case 2: return "后天"
        case let d where d > 2: return "\(d)天后"
        case -1: return "逾期1天"
        default: return "逾期\(-days)天"
        }
    }

    static func money(_ value: Double, currency: String = "CNY") -> String {
        ReminderScheduler.moneyText(value, currency: currency)
    }
}
