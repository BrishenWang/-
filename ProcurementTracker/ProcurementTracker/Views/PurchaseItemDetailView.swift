import SwiftUI
import SwiftData

/// 采购需求详情
struct PurchaseItemDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(ReminderScheduler.self) private var scheduler
    @Environment(FeishuClient.self) private var feishu

    @Bindable var item: PurchaseItem

    @State private var showingEdit = false
    @State private var confirmingDelete = false
    @State private var isSyncing = false

    private var sortedReminders: [ReminderEvent] {
        item.reminders.sorted { $0.fireDate < $1.fireDate }
    }

    var body: some View {
        List {
            summarySection
            infoSection
            remindersSection
            quickActionsSection
        }
        .formStyle(.grouped)
        .navigationTitle(item.title.isEmpty ? "采购需求" : item.title)
        #if os(macOS)
        .navigationSubtitle(item.supplier)
        #endif
        .toolbar {
            #if os(macOS)
            ToolbarItem(placement: .primaryAction) { editButton }
            #else
            ToolbarItem(placement: .topBarTrailing) { editButton }
            #endif
        }
        .sheet(isPresented: $showingEdit) {
            PurchaseItemEditView(item: item, isNew: false)
        }
        .confirmationDialog("确认删除这条采购需求？", isPresented: $confirmingDelete) {
            Button("删除", role: .destructive) { delete() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将同时删除该需求在通知、系统日历和飞书日历中的提醒。")
        }
        .refreshable {
            await sync()
        }
    }

    // MARK: - 摘要

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(item.title.isEmpty ? "未命名采购" : item.title)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    if item.completed {
                        StatusBadge(text: "已归档", color: .gray)
                    }
                }
                HStack(spacing: 6) {
                    StatusBadge(text: item.deliveryStatus.label, color: item.deliveryStatus.color)
                    StatusBadge(text: item.invoiceStatus.label, color: item.invoiceStatus.color)
                    StatusBadge(text: item.paymentStatus.label, color: item.paymentStatus.color)
                }
                if item.unitPrice > 0 {
                    HStack(alignment: .firstTextBaseline) {
                        Text("合计金额")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(AppFormat.money(item.totalPrice, currency: item.currency))
                            .font(.title2.weight(.semibold).monospacedDigit())
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - 详细信息

    private var infoSection: some View {
        Section("采购信息") {
            row("供应商", item.supplier.isEmpty ? "未填写" : item.supplier)
            row("联系人 / 电话", item.contact.isEmpty ? "未填写" : item.contact)
            row("数量", ReminderScheduler.quantityText(item))
            if item.unitPrice > 0 {
                row("单价", AppFormat.money(item.unitPrice, currency: item.currency))
            }
            row("下单日期", AppFormat.day(item.orderDate))
            row("预计大货到货", item.expectedDeliveryDate.map {
                "\(AppFormat.day($0))（\(AppFormat.relativeDay($0))）"
            } ?? "未设置")
            if let actual = item.actualDeliveryDate {
                row("实际到货", AppFormat.day(actual))
            }
            if !item.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("备注").font(.subheadline).foregroundStyle(.secondary)
                    Text(item.notes).textSelection(.enabled)
                }
            }
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }

    // MARK: - 提醒与同步状态

    private var remindersSection: some View {
        Section {
            if sortedReminders.isEmpty {
                Text("当前没有安排提醒。可在编辑中开启到货、催票或自定义提醒。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedReminders) { reminder in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: reminder.kind.sfSymbol)
                                .foregroundStyle(.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reminder.kind.label)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Text(reminder.title)
                                    .font(.subheadline.weight(.medium))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(AppFormat.dateTime(reminder.fireDate))
                                    .font(.caption.monospacedDigit())
                                Text(AppFormat.relativeDay(reminder.fireDate))
                                    .font(.caption2)
                                    .foregroundStyle(reminder.fireDate < Date() ? .red : .secondary)
                            }
                        }

                        HStack(spacing: 14) {
                            ChannelStatusDot(channel: .local, synced: reminder.localScheduled, enabled: item.notifyLocal)
                            ChannelStatusDot(channel: .systemCalendar, synced: reminder.systemSynced, enabled: item.syncSystemCalendar)
                            ChannelStatusDot(channel: .feishu, synced: reminder.feishuSynced, enabled: item.syncFeishu)
                        }

                        if let error = reminder.lastError, !error.isEmpty {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Button {
                Task { await sync() }
            } label: {
                HStack {
                    if isSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text("重新同步提醒")
                }
            }
            .disabled(isSyncing)
        } header: {
            Text("提醒日程")
        } footer: {
            if item.syncFeishu && !feishu.isLoggedIn {
                Text("飞书同步未完成：请在“设置”中登录飞书后回到此页重新同步。")
            }
        }
    }

    // MARK: - 快捷操作

    private var quickActionsSection: some View {
        Section("快捷操作") {
            if item.deliveryStatus != .arrived {
                Button {
                    markArrived()
                } label: {
                    Label("标记为已到货", systemImage: "checkmark.seal")
                }
            }
            if item.invoiceStatus != .issued {
                Button {
                    markIssued()
                } label: {
                    Label("标记为已开票", systemImage: "checkmark.circle.fill")
                }
            }
            Button {
                toggleArchive()
            } label: {
                Label(item.completed ? "取消归档" : "归档此采购",
                      systemImage: item.completed ? "arrow.uturn.backward" : "archivebox")
            }
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("删除采购需求", systemImage: "trash")
            }
        }
    }

    private var editButton: some View {
        Button {
            showingEdit = true
        } label: {
            Label("编辑", systemImage: "square.and.pencil")
        }
    }

    // MARK: - 动作

    private func markArrived() {
        item.actualDeliveryDate = item.actualDeliveryDate ?? Date()
        item.deliveryStatus = .arrived
        persistAndSync()
    }

    private func markIssued() {
        item.invoiceStatus = .issued
        persistAndSync()
    }

    private func toggleArchive() {
        item.completed.toggle()
        persistAndSync()
    }

    private func persistAndSync() {
        item.updatedAt = Date()
        try? modelContext.save()
        let context = modelContext
        let target = item
        Task { await scheduler.reconcile(item: target, in: context) }
    }

    private func sync() async {
        isSyncing = true
        defer { isSyncing = false }
        await scheduler.reconcile(item: item, in: modelContext)
    }

    private func delete() {
        let context = modelContext
        let target = item
        dismiss()
        Task {
            await scheduler.teardown(item: target, in: context)
        }
    }
}
