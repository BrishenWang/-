import SwiftUI
import SwiftData

@main
struct ProcurementTrackerApp: App {
    @State private var services: ServiceContainer

    init() {
        _services = State(initialValue: MainActor.assumeIsolated { ServiceContainer() })
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services.settings)
                .environment(services.feishu)
                .environment(services.scheduler)
                #if os(macOS)
                .frame(minWidth: 960, minHeight: 640)
                #endif
        }
        .modelContainer(Self.sharedContainer)
    }

    static let sharedContainer: ModelContainer = {
        let schema = Schema([PurchaseItem.self, ReminderEvent.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("无法创建数据容器: \(error)")
        }
    }()
}

/// 全局服务装配（飞书客户端、通知、系统日历、提醒调度器）
@MainActor
@Observable
final class ServiceContainer {
    let settings: AppSettings
    let feishu: FeishuClient
    let notifications: NotificationService
    let systemCalendar: SystemCalendarService
    let scheduler: ReminderScheduler

    init() {
        let settings = AppSettings()
        self.settings = settings
        self.feishu = FeishuClient(settings: settings)
        self.notifications = NotificationService()
        self.systemCalendar = SystemCalendarService()
        self.scheduler = ReminderScheduler(
            settings: settings,
            feishu: feishu,
            notifications: notifications,
            systemCalendar: systemCalendar
        )
    }
}
