import SwiftUI

// MARK: - 跨平台颜色

extension Color {
    static var groupedBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
}

// MARK: - 状态配色

extension DeliveryStatus {
    var color: Color {
        switch self {
        case .pending: return .orange
        case .partial: return .blue
        case .arrived: return .green
        }
    }

    var sfSymbol: String {
        switch self {
        case .pending: return "shippingbox"
        case .partial: return "shippingbox.fill"
        case .arrived: return "checkmark.seal"
        }
    }
}

extension InvoiceStatus {
    var color: Color {
        switch self {
        case .notIssued: return .red
        case .urged: return .orange
        case .issued: return .green
        }
    }
}

extension PaymentStatus {
    var color: Color {
        switch self {
        case .unpaid: return .red
        case .partial: return .orange
        case .paid: return .green
        }
    }
}

// MARK: - 状态徽章

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - 统计卡片

struct StatCard: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Spacer()
            }
            Text(value)
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 渠道同步状态图标

struct ChannelStatusDot: View {
    enum Channel {
        case local
        case feishu
        case systemCalendar

        var label: String {
            switch self {
            case .local: return "本地通知"
            case .feishu: return "飞书日历"
            case .systemCalendar: return "系统日历"
            }
        }

        var sfSymbol: String {
            switch self {
            case .local: return "bell.badge"
            case .feishu: return "calendar.badge.clock"
            case .systemCalendar: return "calendar"
            }
        }
    }

    let channel: Channel
    let synced: Bool
    let enabled: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: channel.sfSymbol)
            Text(channel.label)
            Image(systemName: enabled ? (synced ? "checkmark.circle.fill" : "xmark.circle.fill") : "minus.circle")
                .foregroundStyle(enabled ? (synced ? .green : .red) : .secondary.opacity(0.5))
        }
        .font(.caption)
        .foregroundStyle(enabled ? .primary : .secondary)
    }
}
