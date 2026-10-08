import SwiftUI
import VeraBotCore
import VeraBotNetworking

struct BotAvatarAppearanceSaveView: View {
    @Environment(AppState.self) private var app
    @Binding var draft: BotAppearanceDraft
    @State private var bots: [Bot] = []
    @State private var selectedID: Int?
    @State private var gate = BotAppearanceRequestGate()
    @State private var request: Task<Void,Never>?
    @State private var busy = false
    @State private var message: String?
    @State private var confirmClear = false
    private let store = BotAppearanceLabStore()
    private var sessionKey: String { "\(app.sessionGeneration)|\(app.baseURLString)" }
    var body: some View {
        Form {
            Section {
                RobotAvatarView(action:.idle,size:96,appearance:draft.current).frame(maxWidth:.infinity).frame(height:130)
                Text(draft.isDirty ? "当前有未保存草稿" : "当前草稿与上次载入或保存一致").font(.footnote).foregroundStyle(.secondary)
            }
            Section("本机外观") {
                Button("保存到本机") { local { try store.save(draft.current); draft.markSaved(); return "已保存到本机" } }
                Button("加载本机外观") {
                    local {
                        guard let value = try store.load() else { return "本机尚未保存外观" }
                        try requireInstalled(value)
                        draft = BotAppearanceDraft(saved:value)
                        return "已加载本机外观"
                    }
                }
                Button("取消草稿修改") { draft.cancel(); message = "已恢复上次载入或保存的外观" }
                Button("恢复实验室默认外观") {
                    local { try draft.update(.robotDefault); return "默认外观已进入草稿，尚未保存" }
                }
            }.disabled(busy)
            Section {
                Picker("目标 Bot",selection:$selectedID) {
                    Text("请选择 Bot").tag(Int?.none)
                    ForEach(bots) { bot in Text(bot.name).tag(Int?.some(bot.id)) }
                }.disabled(busy)
                Button("刷新 Bot 列表") { loadBots() }.disabled(busy)
                Button("读取此外观") { remote(.read) }.disabled(busy || selectedID == nil)
                Button("保存草稿到此 Bot") { remote(.save) }.disabled(busy || selectedID == nil)
                Button("清除此 Bot 的外观配置",role:.destructive) { confirmClear = true }
                    .disabled(busy || selectedID == nil)
                if busy { ProgressView("正在处理…") }
            } header: {
                Text("指定 Bot 外观")
            } footer: {
                Text("保存后，正式界面会使用该新版形象，并随 Bot 执行状态变化。已设置的相册照片仍优先显示。")
            }
            if let message { Section { Text(message).font(.footnote) } }
        }
        .navigationTitle("外观配置").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("清除所选 Bot 的外观配置？",isPresented:$confirmClear,titleVisibility:.visible) {
            Button("清除外观配置",role:.destructive) { remote(.clear) }
        }
        .task { loadBots() }
        .onChange(of:selectedID) { _,_ in invalidate(); message = nil }
        .onChange(of:sessionKey) { _,_ in invalidate(); selectedID = nil; bots = []; message = nil }
        .onDisappear { invalidate() }
    }
    private enum Operation { case read,save,clear }
    private func requireInstalled(_ value:BotAppearance) throws {
        guard BotAvatarTemplateRegistry.resolve(id:value.templateID,version:value.templateVersion) != nil else {
            throw BotAppearanceError.invalid("此形象暂未安装，已保留原配置")
        }
    }
    private func local(_ operation:() throws -> String) {
        do { message = try operation() } catch { message = "未完成，草稿和原配置已保留：\(error.localizedDescription)" }
    }
    private func invalidate() { gate.invalidate(); request?.cancel(); request = nil; busy = false }
    private func accepts(_ ticket:BotAppearanceRequestGate.Ticket) -> Bool {
        !Task.isCancelled && gate.accepts(ticket,botID:selectedID,generation:app.sessionGeneration,server:app.baseURLString)
    }
    private func loadBots() {
        invalidate()
        let ticket = gate.begin(botID:selectedID,generation:app.sessionGeneration,server:app.baseURLString)
        let api = app.api
        busy = true
        request = Task { @MainActor in
            do {
                let result = try await api.bots()
                guard accepts(ticket) else { return }
                bots = result.bots
                if let selectedID, !bots.contains(where: { $0.id == selectedID }) { self.selectedID = nil }
                message = bots.isEmpty ? "尚无可选择的 Bot" : nil
            } catch {
                guard accepts(ticket) else { return }; message = error.localizedDescription
            }
            busy = false
        }
    }
    private func remote(_ operation:Operation) {
        guard let id = selectedID else { return }
        invalidate()
        let ticket = gate.begin(botID:id,generation:app.sessionGeneration,server:app.baseURLString)
        let api = app.api
        let submitted = draft.current
        busy = true; message = nil
        request = Task { @MainActor in
            do {
                switch operation {
                case .read:
                    // Refresh before reading; the list snapshot is not a save receipt.
                    let result = try await api.bots()
                    guard accepts(ticket) else { return }
                    guard let bot = result.bots.first(where: { $0.id == id }) else { throw BotAppearanceError.invalid("目标 Bot 已不存在") }
                    guard bot.appearanceFieldPresent else { throw BotAppearanceSaveError.unverifiedResponse }
                    guard let raw = bot.appearance else { message = "此 Bot 尚无外观配置，草稿已保留"; busy = false; return }
                    let value = try JSONDecoder().decode(BotAppearance.self,from:JSONEncoder().encode(raw))
                    try requireInstalled(value)
                    draft = BotAppearanceDraft(saved:value)
                    message = "已读取 \(bot.name) 的外观"
                case .save:
                    let bot = try await BotAppearanceSaveService(api:api).save(botID:id,appearance:submitted)
                    guard accepts(ticket) else { return }
                    // Do not mark subsequent edits as saved by an earlier request.
                    if draft.current == submitted { draft.markSaved() }
                    message = "已确认保存到 \(bot.name)，正式头像暂未切换"
                case .clear:
                    let bot = try await BotAppearanceSaveService(api:api).save(botID:id,appearance:nil)
                    guard accepts(ticket) else { return }
                    message = "已确认清除 \(bot.name) 的外观配置，当前草稿已保留"
                }
            } catch {
                guard accepts(ticket) else { return }
                message = "未完成，草稿已保留：\(error.localizedDescription)"
            }
            busy = false
        }
    }
}
