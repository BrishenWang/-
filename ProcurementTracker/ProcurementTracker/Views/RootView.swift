import SwiftUI
import SwiftData

struct RootView: View {
    enum SidebarItem: String, CaseIterable, Identifiable {
        case dashboard = "待办概览"
        case purchases = "采购需求"
        case settings = "设置"

        var id: String { rawValue }

        var sfSymbol: String {
            switch self {
            case .dashboard: return "checklist.checked"
            case .purchases: return "shippingbox"
            case .settings: return "gearshape"
            }
        }
    }

    #if os(macOS)
    @State private var selection: SidebarItem? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.sfSymbol)
            }
            .navigationTitle("采购管家")
        } detail: {
            switch selection ?? .dashboard {
            case .dashboard:
                DashboardView()
            case .purchases:
                PurchaseItemListView()
            case .settings:
                SettingsView()
            }
        }
    }
    #else
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("待办", systemImage: "checklist.checked") }
            PurchaseItemListView()
                .tabItem { Label("采购", systemImage: "shippingbox") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
    }
    #endif
}
