import SwiftUI
import VeraBotCore
import VeraBotTTS

@main
struct VeraBotApp: App {
    @State private var app = AppState()
    @State private var player = SpeechPlayer()   // 全局语音播放（TTS）
    @AppStorage(SettingsKeys.appearance) private var appearanceRaw = AppearanceMode.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(player)
                .tint(.brand)   // 全局强调色：按钮、导航、进度条、Tab 选中态
                .dismissKeyboardOnBackground()   // App 进入后台时收起键盘
                .preferredColorScheme((AppearanceMode(rawValue: appearanceRaw) ?? .system).colorScheme)   // 设置 › 外观
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        if app.token == nil {
            LoginView()
        } else {
            MainTabView()
        }
    }
}

struct MainTabView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            BotListView()
                .tabItem { Label("助理", systemImage: "bubble.left.and.bubble.right") }
                .tag(0)
            RemindersView()
                .tabItem { Label("提醒", systemImage: "alarm") }
                .badge(app.unreadCount)
                .tag(1)
            PlaygroundView()
                .tabItem { Label("游乐场", systemImage: "gamecontroller") }
                .tag(2)
            IslandView()
                .tabItem { Label("小岛", systemImage: "leaf") }
                .tag(3)
            ExploreIdeasView()
                .tabItem { Label("探索", systemImage: "sparkle.magnifyingglass") }
                .tag(4)
        }
        .task {
            await app.refreshProfile()
            NotificationCoordinator.shared.start(app: app)
            await app.syncReminders()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await app.syncReminders() } }
        }
        .alert("提示", isPresented: Binding(
            get: { app.missingNotice != nil },
            set: { if !$0 { app.missingNotice = nil } }
        )) {
            Button("好") { app.missingNotice = nil }
        } message: {
            Text(app.missingNotice ?? "")
        }
        .sheet(isPresented: $app.showNotificationSettings) {
            NavigationStack {
                NotificationSettingsView()
            }
        }
    }
}
