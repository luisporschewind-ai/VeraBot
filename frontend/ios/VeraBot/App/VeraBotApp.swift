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

    var body: some View {
        TabView {
            BotListView()
                .tabItem { Label("助理", systemImage: "bubble.left.and.bubble.right") }
            RemindersView()
                .tabItem { Label("提醒", systemImage: "alarm") }
        }
        .task { await app.refreshProfile() }
    }
}
