import SwiftUI
import SwiftData

/// 待办概览：逾期 / 今日提醒、关键统计、近期日程
struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ReminderScheduler.self) private var scheduler

    @Query(sort: \PurchaseItem.createdAt, order: .reverse) private var allItems: [PurchaseItem]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statsGrid
                    pendingSection
                    upcomingSection
                }
                .padding()
            }
            .background(Color.groupedBackground)
            .navigationTitle("待办概览")
            .navigationDestination(for: PurchaseItem.self) { item in
                PurchaseItemDetailView(item: item)
            }
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .primaryAction) { addButton }
                #else
                ToolbarItem(placement: .topBarTrailing) { addButton }
                #endif
            }
            .sheet(item: $newItem) { item in
                PurchaseItemEditView(item: item, isNew: true)
            }
        }
    }

    // MARK: - 数据计算

    private var activeItems: [PurchaseItem] {
        allItems.filter { !$0.completed }
    }

    private var pendingCount: Int {
        activeItems.filter { $0.deliveryStatus != .arrived }.count
    }

    private var invoicePendingCount: Int {
        activeItems.filter { $0.invoiceStatus != .issued }.count
    }

    private var monthAmount: Double {
        let calendar = Calendar.current
        return allItems
            .filter { item in
                guard let date = item.orderDate else { return false }
                return calendar.isDate(date, equalTo: Date(), toGranularity: .month)
            }
            .reduce(0) { $0 + $1.totalPrice }
    }

    /// 已到提醒时间但采购未完结的提醒
    private var pendingReminders: [(ReminderEvent, PurchaseItem)] {
        let endOfToday = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date()
        return activeItems
            .flatMap { item in item.reminders.compactMap { reminder in
                guard let owner = reminder.item, !owner.completed else { return nil }
                return (reminder, owner)
            } }
            .filter { $0.0.fireDate <= endOfToday }
            .sorted { $0.0.fireDate < $1.0.fireDate }
    }

    /// 未来 7 天内的提醒
    private var upcomingReminders: [(ReminderEvent, PurchaseItem)] {
        let calendar = Calendar.current
        guard let inSevenDays = calendar.date(byAdding: .day, value: 7, to: Date()) else { return [] }
        return activeItems
            .flatMap { item in item.reminders.map { ($0, item) } }
            .filter { $0.0.fireDate > Date() && $0.0.fireDate <= inSevenDays }
            .sorted { $0.0.fireDate < $1.0.fireDate }
    }

    // MARK: - 子视图

    private var statsGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            StatCard(title: "进行中采购", value: "\(activeItems.count)", systemImage: "shippingbox", tint: .blue)
            StatCard(title: "待到货", value: "\(pendingCount)", systemImage: "truck.box", tint: .orange)
            StatCard(title: "待收发票", value: "\(invoicePendingCount)", systemImage: "doc.text", tint: .red)
            StatCard(title: "本月采购额", value: AppFormat.money(monthAmount), systemImage: "yensign.circle", tint: .green)
        }
    }

    @ViewBuilder
    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("需要处理（\(pendingReminders.count)）", systemImage: "exclamationmark.bell")
                .font(.headline)
                .foregroundStyle(pendingReminders.isEmpty ? .secondary : .red)

            if pendingReminders.isEmpty {
                Text("暂无逾期或今日待办，新的采购提醒会出现在这里。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(pendingReminders, id: \.0.id) { pair in
                    NavigationLink(value: pair.1) {
                        ReminderRow(reminder: pair.0, item: pair.1, urgent: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("未来 7 天", systemImage: "calendar")
                .font(.headline)
                .foregroundStyle(.secondary)

            if upcomingReminders.isEmpty {
                Text("未来 7 天没有安排提醒。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(upcomingReminders, id: \.0.id) { pair in
                    NavigationLink(value: pair.1) {
                        ReminderRow(reminder: pair.0, item: pair.1, urgent: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 新增

    @State private var newItem: PurchaseItem?

    private var addButton: some View {
        Button {
            let item = PurchaseItem()
            scheduler.settings.applyDefaults(to: item)
            modelContext.insert(item)
            newItem = item
        } label: {
            Label("新增采购", systemImage: "plus")
        }
    }
}

/// 概览页中的提醒行
private struct ReminderRow: View {
    let reminder: ReminderEvent
    let item: PurchaseItem
    let urgent: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: reminder.kind.sfSymbol)
                .font(.title3)
                .foregroundStyle(urgent ? .red : .accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(reminder.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text("\(item.title) · \(AppFormat.dateTime(reminder.fireDate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(AppFormat.relativeDay(reminder.fireDate))
                .font(.caption.weight(.semibold))
                .foregroundStyle(urgent ? .red : .secondary)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }
}
