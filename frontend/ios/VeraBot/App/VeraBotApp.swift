import SwiftUI
import VeraBotCore
import VeraBotTTS

@main
struct VeraBotApp: App {
    @UIApplicationDelegateAdaptor(LibraryAppDelegate.self) private var libraryDelegate
    @State private var app: AppState
    init() {
        let state = AppState()
        _app = State(initialValue: state)
        NotificationCoordinator.shared.start(app: state)
    }
    @State private var travelStore = BotTravelStore()
    @State private var player = SpeechPlayer()   // 全局语音播放（TTS）
    @AppStorage(SettingsKeys.appearance) private var appearanceRaw = AppearanceMode.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(travelStore)
                .environment(player)
                .tint(AppearanceMode(rawValue: appearanceRaw) == .native ? .primary : .brand)
                .dismissKeyboardOnBackground()   // App 进入后台时收起键盘
                .background(AppearanceWindowSync(mode: AppearanceMode(rawValue: appearanceRaw) ?? .system)
                    .frame(width: 0, height: 0).accessibilityHidden(true))
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(SpeechPlayer.self) private var player
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var noticeCenter = BotNoticeCenter()
    @State private var welcoming = true

    var body: some View {
        ZStack {
            Group {
                if app.token == nil { LoginView() } else { MainTabView() }
            }
            .allowsHitTesting(!welcoming)
            .accessibilityHidden(welcoming)
            if welcoming { BotLaunchView().transition(.opacity).zIndex(1) }
        }
        .environment(noticeCenter)
        .botNoticeHost(noticeCenter) { entry in
            if let link = entry.message.link { Task { await app.open(link: link) } }
            noticeCenter.dismiss(id: entry.id)
        }
        .task(id: "\(app.userID ?? 0)|\(scenePhase == .active)|\(app.baseURLString)") {
            app.notificationEvents.attach(noticeCenter)
            app.notificationEvents.isForeground = scenePhase == .active
            guard scenePhase == .active, app.token != nil else { return }
            await NotificationCoordinator.shared.resumePendingTap()
            await app.notificationEvents.run()
        }
        .task {
            do {
                // Three greetings stagger over 0.8s; each existing .send action lasts about 1.46s.
                // Leave a short pause after the last Bot finishes before fading into the app.
                try await Task.sleep(for: .milliseconds(reduceMotion ? 350 : 2600))
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { welcoming = false }
            } catch { /* Root dismissal cancels the welcome. */ }
        }
        .task(id:"library-\(app.userID ?? 0)-\(app.baseURLString)-\(scenePhase == .active)") {
            guard scenePhase == .active,app.token != nil else { return }
            await app.refreshLibrary()
        }
        .onChange(of: scenePhase) { _, phase in
            app.setActivityForeground(phase == .active)
            if phase == .background { player.stop() }
        }
        .onChange(of: app.token) { _, token in
            if token == nil {
                player.stop()
                noticeCenter.clear()
            }
        }
        .onChange(of: app.userID) { _, _ in
            player.stop()
            noticeCenter.clear()
        }
        .onChange(of: app.selectedTab) { _, _ in noticeCenter.clear() }
    }
}

struct MainTabView: View {
    @Environment(AppState.self) private var app
    @Environment(BotTravelStore.self) private var travelStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            BotListView()
                .tabItem { Label("助理", systemImage: "bubble.left.and.bubble.right") }
                .tag(0)
            FeedView()
                .tabItem { Label("发现", systemImage: "newspaper") }
                .tag(5)
            PlaygroundView()
                .tabItem { Label("游乐场", systemImage: "gamecontroller") }
                .tag(2)
            RemindersView()
                .tabItem { Label("安排", systemImage: "alarm") }
                .badge(app.unreadCount)
                .tag(1)
            ExploreIdeasView()
                .tabItem { Label("空间", systemImage: "sparkle.magnifyingglass") }
                .tag(4)
        }
        .task {
            await app.refreshProfile()
            travelStore.configure(userID: app.userID)
            NotificationCoordinator.shared.start(app: app)
            await app.syncReminders()
        }
        .task {
            while !Task.isCancelled {
                travelStore.refresh()
                do { try await Task.sleep(for: .seconds(1)) }
                catch { break }
            }
        }
        .onChange(of: app.userID) { _, userID in travelStore.configure(userID: userID) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                travelStore.refresh()
                Task { await app.syncReminders() }
            }
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
