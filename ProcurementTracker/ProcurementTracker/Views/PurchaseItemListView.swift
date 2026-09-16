import SwiftUI
import SwiftData

/// 采购需求列表
struct PurchaseItemListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ReminderScheduler.self) private var scheduler

    @Query(sort: \PurchaseItem.createdAt, order: .reverse) private var allItems: [PurchaseItem]

    @State private var searchText = ""
    @State private var filter: ListFilter = .active
    @State private var newItem: PurchaseItem?

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredItems, id: \.id) { item in
                    NavigationLink(value: item) {
                        PurchaseItemRow(item: item)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            delete(item)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        Button {
                            toggleArchive(item)
                        } label: {
                            Label(item.completed ? "取消归档" : "归档",
                                  systemImage: item.completed ? "arrow.uturn.backward" : "archivebox")
                        }
                        .tint(.gray)
                    }
                }
            }
            .navigationTitle("采购需求")
            .searchable(text: $searchText, prompt: "搜索物品、供应商、联系人")
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
            .safeAreaInset(edge: .top) {
                filterBar
            }
            .overlay {
                if filteredItems.isEmpty {
                    ContentUnavailableViewCompat()
                }
            }
            .sheet(item: $newItem) { item in
                PurchaseItemEditView(item: item, isNew: true)
            }
        }
    }

    // MARK: - 筛选

    enum ListFilter: String, CaseIterable, Identifiable {
        case active = "进行中"
        case delivering = "待到货"
        case invoicing = "待收票"
        case all = "全部"
        case archived = "已归档"

        var id: String { rawValue }
    }

    private var filteredItems: [PurchaseItem] {
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        let result = allItems.filter { item in
            switch filter {
            case .all:
                true
            case .active:
                !item.completed
            case .delivering:
                !item.completed && item.deliveryStatus != .arrived
            case .invoicing:
                !item.completed && item.invoiceStatus != .issued
            case .archived:
                item.completed
            }
        }.filter { item in
            guard !keyword.isEmpty else { return true }
            return item.title.localizedCaseInsensitiveContains(keyword)
                || item.supplier.localizedCaseInsensitiveContains(keyword)
                || item.contact.localizedCaseInsensitiveContains(keyword)
                || item.notes.localizedCaseInsensitiveContains(keyword)
        }

        return result.sorted { lhs, rhs in
            if lhs.completed != rhs.completed { return !lhs.completed }
            switch (lhs.expectedDeliveryDate, rhs.expectedDeliveryDate) {
            case let (l?, r?): return l < r
            case (nil, _?): return false
            case (_?, nil): return true
            default: return lhs.createdAt > rhs.createdAt
            }
        }
    }

    private var filterBar: some View {
        Picker("筛选", selection: $filter) {
            ForEach(ListFilter.allCases) { filter in
                Text(filter.rawValue).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var addButton: some View {
        Button {
            let item = PurchaseItem()
            scheduler.settings.applyDefaults(to: item)
            modelContext.insert(item)
            newItem = item
        } label: {
            Label("新增", systemImage: "plus")
        }
    }

    // MARK: - 操作

    private func delete(_ item: PurchaseItem) {
        Task { await scheduler.teardown(item: item, in: modelContext) }
    }

    private func toggleArchive(_ item: PurchaseItem) {
        item.completed.toggle()
        item.updatedAt = Date()
        try? modelContext.save()
        Task { await scheduler.reconcile(item: item, in: modelContext) }
    }
}

/// 列表行
struct PurchaseItemRow: View {
    let item: PurchaseItem

    private var overdue: Bool {
        guard let date = item.expectedDeliveryDate, item.deliveryStatus != .arrived, !item.completed else {
            return false
        }
        return date < Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.title.isEmpty ? "未命名采购" : item.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if item.unitPrice > 0 {
                    Text(AppFormat.money(item.totalPrice, currency: item.currency))
                        .font(.subheadline.monospacedDigit())
                }
            }

            HStack(spacing: 6) {
                Text(item.supplier.isEmpty ? "未填供应商" : item.supplier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                StatusBadge(text: item.deliveryStatus.label, color: item.deliveryStatus.color)
                StatusBadge(text: item.invoiceStatus.label, color: item.invoiceStatus.color)
            }

            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.caption2)
                Text(item.expectedDeliveryDate.map { "预计到货 \($0, format: .dateTime.year().month().day())" } ?? "未设置到货日期")
                if let date = item.expectedDeliveryDate, !item.completed {
                    Text("· \(AppFormat.relativeDay(date))")
                        .foregroundStyle(overdue ? .red : .secondary)
                }
            }
            .font(.caption2)
            .foregroundStyle(overdue ? .red : .secondary)
        }
        .padding(.vertical, 4)
        .opacity(item.completed ? 0.55 : 1)
    }
}

/// 空状态（兼容 macOS 14 / iOS 17）
struct ContentUnavailableViewCompat: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("没有符合条件的采购需求")
                .font(.headline)
            Text("点击右上角“新增”按钮，记录一条新的采购需求。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
