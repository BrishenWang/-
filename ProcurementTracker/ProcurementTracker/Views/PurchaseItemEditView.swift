import SwiftUI
import SwiftData

/// 新增 / 编辑采购需求
struct PurchaseItemEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(ReminderScheduler.self) private var scheduler
    @Environment(FeishuClient.self) private var feishu

    @Bindable var item: PurchaseItem
    let isNew: Bool

    @State private var notesDraft: String = ""

    private var titleInvalid: Bool {
        item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                basicSection
                deliverySection
                reminderRuleSection
                channelSection
                notesSection
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "新增采购需求" : "编辑采购需求")
            #if os(macOS)
            .frame(minWidth: 560, minHeight: 640)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(titleInvalid)
                }
            }
            .onAppear {
                notesDraft = item.notes
            }
        }
    }

    // MARK: - 基本信息

    private var basicSection: some View {
        Section("基本信息") {
            TextField("物品 / 采购名称（必填）", text: $item.title)
            TextField("供应商", text: $item.supplier)
            TextField("供应商联系人 / 电话", text: $item.contact)

            HStack {
                TextField("数量", value: $item.quantity, format: .number)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                TextField("单位", text: $item.unit)
                    .frame(width: 80)
            }

            HStack {
                TextField("单价", value: $item.unitPrice, format: .number)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                Picker("", selection: $item.currency) {
                    Text("人民币 ￥").tag("CNY")
                    Text("美元 $").tag("USD")
                    Text("欧元 €").tag("EUR")
                }
                .labelsHidden()
                .frame(width: 120)
            }

            HStack {
                Text("合计金额")
                Spacer()
                Text(AppFormat.money(item.totalPrice, currency: item.currency))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            DatePicker("下单日期", selection: Binding(
                get: { item.orderDate ?? Date() },
                set: { item.orderDate = $0 }
            ), displayedComponents: .date)
        }
    }

    // MARK: - 交期与状态

    private var deliverySection: some View {
        Section("交期与状态") {
            Picker("到货状态", selection: Binding(
                get: { item.deliveryStatus },
                set: { item.deliveryStatus = $0 }
            )) {
                ForEach(DeliveryStatus.allCases) { status in
                    Text(status.label).tag(status)
                }
            }

            Toggle("设置预计大货到货日期", isOn: Binding(
                get: { item.expectedDeliveryDate != nil },
                set: { enabled in
                    if enabled {
                        item.expectedDeliveryDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())
                    } else {
                        item.expectedDeliveryDate = nil
                    }
                }
            ))
            if let expectedBinding = Binding($item.expectedDeliveryDate) {
                DatePicker("预计到货日期", selection: expectedBinding, displayedComponents: .date)
            }

            Toggle("已实际到货", isOn: Binding(
                get: { item.actualDeliveryDate != nil },
                set: { enabled in
                    if enabled {
                        item.actualDeliveryDate = Date()
                        item.deliveryStatus = .arrived
                    } else {
                        item.actualDeliveryDate = nil
                    }
                }
            ))
            if let actualBinding = Binding($item.actualDeliveryDate) {
                DatePicker("实际到货日期", selection: actualBinding, displayedComponents: .date)
            }

            Picker("发票状态", selection: Binding(
                get: { item.invoiceStatus },
                set: { item.invoiceStatus = $0 }
            )) {
                ForEach(InvoiceStatus.allCases) { status in
                    Text(status.label).tag(status)
                }
            }

            Picker("付款状态", selection: Binding(
                get: { item.paymentStatus },
                set: { item.paymentStatus = $0 }
            )) {
                ForEach(PaymentStatus.allCases) { status in
                    Text(status.label).tag(status)
                }
            }
        }
    }

    // MARK: - 提醒规则

    private var reminderRuleSection: some View {
        Section("提醒规则") {
            Toggle("大货到货提醒", isOn: $item.deliveryReminderEnabled)
            if item.deliveryReminderEnabled {
                Stepper(value: $item.deliveryReminderDaysBefore, in: 0...30) {
                    Text(item.deliveryReminderDaysBefore == 0
                         ? "仅到货当天提醒"
                         : "提前 \(item.deliveryReminderDaysBefore) 天预告")
                }
            }

            Toggle("催开发票提醒", isOn: $item.invoiceReminderEnabled)
            if item.invoiceReminderEnabled {
                Stepper(value: $item.invoiceReminderDaysAfter, in: 0...60) {
                    Text(item.invoiceReminderDaysAfter == 0
                         ? "到货当天即提醒催票"
                         : "到货 \(item.invoiceReminderDaysAfter) 天后催要发票")
                }
            }

            Toggle("自定义跟进提醒", isOn: $item.customReminderEnabled)
            if item.customReminderEnabled {
                DatePicker(
                    "提醒时间",
                    selection: Binding(
                        get: { item.customReminderDate ?? Date().addingTimeInterval(3600) },
                        set: { item.customReminderDate = $0 }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
            }
        }
    }

    // MARK: - 提醒渠道

    private var channelSection: some View {
        Section("提醒渠道") {
            Toggle(isOn: $item.notifyLocal) {
                Label("本机通知", systemImage: "bell.badge")
            }
            Toggle(isOn: $item.syncSystemCalendar) {
                Label("写入系统日历", systemImage: "calendar")
            }
            Toggle(isOn: $item.syncFeishu) {
                Label("同步到飞书日历", systemImage: "calendar.badge.clock")
            }
            if item.syncFeishu && !feishu.isLoggedIn {
                Label("尚未登录飞书，请先在“设置”中完成授权，保存后可在详情页重试同步。", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text("飞书日历会创建带提醒的日程，在飞书客户端和你的所有设备上推送；系统日历可通过 iCloud 在 iPhone 与 Mac 间同步。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 备注

    private var notesSection: some View {
        Section("备注") {
            TextEditor(text: $notesDraft)
                .frame(minHeight: 90)
                .overlay(alignment: .topLeading) {
                    if notesDraft.isEmpty {
                        Text("物流单号、规格要求、对接人等补充信息")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                }
        }
    }

    // MARK: - 保存 / 取消

    private func save() {
        item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.supplier = item.supplier.trimmingCharacters(in: .whitespacesAndNewlines)
        item.notes = notesDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        item.updatedAt = Date()
        if item.orderDate == nil {
            item.orderDate = Date()
        }
        if item.actualDeliveryDate != nil && item.deliveryStatus == .pending {
            item.deliveryStatus = .arrived
        }

        try? modelContext.save()
        let context = modelContext
        let savedItem = item
        Task { await scheduler.reconcile(item: savedItem, in: context) }
        dismiss()
    }

    private func cancel() {
        if isNew {
            modelContext.delete(item)
            try? modelContext.save()
        }
        dismiss()
    }
}
