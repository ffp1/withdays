import SwiftUI

@main
struct WithDaysApp: App {
    @State private var store = CalendarStore()
    @State private var templates = TemplateStore()
    @State private var todos = TodoStore()
    @State private var toasts = ToastCenter()
    @AppStorage(SettingsKey.theme, store: AppGroup.defaults) private var theme = AppTheme.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(templates)
                .environment(todos)
                .environment(toasts)
                .tint(.brand)
                .preferredColorScheme((AppTheme(rawValue: theme) ?? .system).colorScheme)
        }
    }
}

struct RootView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch store.access {
            case .granted:
                HomeView()
            case .undetermined:
                Color(.systemBackground)
                    .ignoresSafeArea()
                    .task { await store.requestAccess() }
            case .denied:
                AccessDeniedView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Access may have been granted in the Settings app while we were away.
            if phase == .active { store.refreshStatus() }
        }
    }
}

struct AccessDeniedView: View {
    var body: some View {
        ContentUnavailableView {
            Label("カレンダーへのアクセスが必要です", systemImage: "calendar.badge.exclamationmark")
        } description: {
            Text("WithDays は Appleのカレンダーの予定をそのまま表示・編集します。設定で「カレンダー」を「フルアクセス」にしてください。")
        } actions: {
            Button("設定を開く") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.glassProminent)
        }
    }
}
