import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Environment(FeishuClient.self) private var feishu
    @Environment(ReminderScheduler.self) private var scheduler

    @Query private var allItems: [PurchaseItem]

    @State private var loginError: String?
    @State private var loginInProgress = false
    @State private var syncMessage: String?
    @State private var exportDocument: JSONBackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var importMessage: String?

    private let timezones = [
        "Asia/Shanghai",
        "Asia/Hong_Kong",
        "Asia/Tokyo",
        "Asia/Singapore",
        "Europe/London",
        "America/Los_Angeles",
        "America/New_York"
    ]

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                feishuSection($settings)
                defaultsSection($settings)
                permissionSection
                dataSection
                aboutSection
            }
            .formStyle(.grouped)
            .navigationTitle("设置")
            .alert("飞书授权提示", isPresented: Binding(
                get: { loginError != nil },
                set: { if !$0 { loginError = nil } }
            )) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(loginError ?? "")
            }
            .alert("导入结果", isPresented: Binding(
                get: { importMessage != nil },
                set: { if !$0 { importMessage = nil } }
            )) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(importMessage ?? "")
            }
            .fileExporter(
                isPresented: $showExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: exportFilename
            ) { _ in }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
        }
    }

    // MARK: - 飞书集成

    @ViewBuilder
    private func feishuSection(_ settings: Bindable<AppSettings>) -> some View {
        Section {
            Picker("飞书站点", selection: settings.feishuDomainRaw) {
                ForEach(FeishuDomain.allCases) { domain in
                    Text(domain.label).tag(domain.rawValue)
                }
            }

            TextField("App ID（cli_ 开头）", text: settings.feishuAppID)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
            SecureField("App Secret", text: settings.feishuAppSecret)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
            TextField("重定向地址 Redirect URI", text: settings.redirectURI)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()

            Picker("日程时区", selection: settings.timezoneIdentifier) {
                Text("跟随系统").tag(TimeZone.current.identifier)
                ForEach(timezones, id: \.self) { tz in
                    Text(tz).tag(tz)
                }
            }

            if feishu.isLoggedIn {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("已登录：\(feishu.displayName)")
                    Spacer()
                    Button("退出登录", role: .destructive) {
                        feishu.logout()
                    }
                }
                Button {
                    Task { await syncAll() }
                } label: {
                    Label("立即同步全部提醒到飞书", systemImage: "arrow.triangle.2.circlepath")
                }
                if let syncMessage {
                    Text(syncMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Task { await login() }
                } label: {
                    HStack {
                        if loginInProgress {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "person.badge.key")
                        }
                        Text(loginInProgress ? "正在授权…" : "登录飞书并授权日历")
                    }
                }
                .disabled(loginInProgress || settings.feishuAppID.wrappedValue.isEmpty)
            }
        } header: {
            Text("飞书日历集成")
        } footer: {
            Text("授权后，采购到货、催开发票等提醒会自动创建为飞书日程，由飞书推送提醒。")
        }

        Section {
            DisclosureGroup("如何创建飞书自建应用？") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. 用电脑打开 open.feishu.cn/app，点击“创建企业自建应用”。")
                    Text("2. 进入“权限管理”，开通以下权限并发布版本：")
                    Text("   · 更新日历及日程信息（calendar:calendar）").font(.caption.monospaced())
                    Text("   · 离线访问已授权数据（offline_access）").font(.caption.monospaced())
                    Text("3. 进入“安全设置 → 重定向 URL”，添加：")
                    Text("   procurement-tracker://oauth/callback").font(.caption.monospaced())
                    Text("   若后台不允许自定义协议地址，可改填一个你自己的 HTTPS 网址，并把它完整填写到上方“重定向地址”，App 会在浏览器跳转时自动拦截，该页面无需真实存在。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("4. 应用需创建版本并发布，由企业管理员审核通过后可用。")
                    Text("5. 把应用的 App ID、App Secret 填入上方，点击登录授权。")
                }
                .font(.caption)
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - 默认提醒规则

    private func defaultsSection(_ settings: Bindable<AppSettings>) -> some View {
        Section("新建采购的默认设置") {
            Picker("默认提醒时刻", selection: settings.defaultReminderHour) {
                ForEach(Array(7...20), id: \.self) { hour in
                    Text(String(format: "%02d:00", hour)).tag(hour)
                }
            }

            Stepper(value: settings.defaultDeliveryDaysBefore, in: 0...30) {
                Text("到货前默认提前 \(settings.defaultDeliveryDaysBefore.wrappedValue) 天预告")
            }
            Stepper(value: settings.defaultInvoiceDaysAfter, in: 0...60) {
                Text("到货后默认 \(settings.defaultInvoiceDaysAfter.wrappedValue) 天催要发票")
            }

            Toggle("默认开启本机通知", isOn: settings.defaultLocalEnabled)
            Toggle("默认同步飞书日历", isOn: settings.defaultFeishuEnabled)
            Toggle("默认写入系统日历", isOn: settings.defaultSystemCalendarEnabled)
        }
    }

    // MARK: - 系统权限

    private var permissionSection: some View {
        Section("系统权限") {
            Button {
                Task { _ = try? await scheduler.notifications.requestAuthorization() }
            } label: {
                Label("开启通知权限", systemImage: "bell.badge")
            }
            Button {
                Task { try? await scheduler.systemCalendar.requestWriteAccess() }
            } label: {
                Label("授权写入系统日历", systemImage: "calendar")
            }
            Text("可随时在“系统设置 → 通知 / 日历”中修改授权。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 数据备份

    private var dataSection: some View {
        Section("数据备份") {
            Button {
                exportBackup()
            } label: {
                Label("导出全部采购需求（JSON）", systemImage: "square.and.arrow.up")
            }
            Button {
                showImporter = true
            } label: {
                Label("从 JSON 备份导入", systemImage: "square.and.arrow.down")
            }
            Text("数据默认保存在本机；导出的 JSON 可在 iPhone 与 Mac 之间迁移。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 关于

    private var aboutSection: some View {
        Section("关于") {
            HStack {
                Text("采购管家")
                Spacer()
                Text("版本 1.0").foregroundStyle(.secondary)
            }
            Text("面向采购人的轻量工具：记录采购需求，跟踪大货到货，自动催要发票，并把提醒同步到飞书日历。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 动作

    private var exportFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return "采购管家备份-\(formatter.string(from: Date()))"
    }

    private func login() async {
        loginInProgress = true
        defer { loginInProgress = false }
        do {
            try await feishu.login()
            await scheduler.reconcileAll(in: modelContext)
            syncMessage = "飞书日历连接成功，已同步现有采购提醒。"
        } catch FeishuError.loginCancelled {
            // 用户主动取消，不提示
        } catch {
            loginError = error.localizedDescription
        }
    }

    private func syncAll() async {
        await scheduler.reconcileAll(in: modelContext)
        syncMessage = scheduler.lastMessage
    }

    private func exportBackup() {
        do {
            let data = try BackupService.exportData(items: allItems)
            exportDocument = JSONBackupDocument(data: data)
            showExporter = true
        } catch {
            importMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try Data(contentsOf: url)
            let count = try BackupService.importData(data, into: modelContext)
            importMessage = "成功导入 \(count) 条采购需求，正在重建提醒…"
            Task { await scheduler.reconcileAll(in: modelContext) }
        } catch {
            importMessage = "导入失败：\(error.localizedDescription)"
        }
    }
}
