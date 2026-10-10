import SwiftUI
import VeraBotCore

struct CreateBotSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let onCreated: @MainActor () -> Void

    @State private var draft = BotCreate(name: "", avatar: BotAvatarFigure.default.rawValue, color: BotAvatarColorPalette.defaultColor, persona: "", instructions: "")
    @State private var saving = false
    @State private var errorText: String?
    @State private var tagsText = ""   // 「搜索, 查询, 调研」；保存时 BotTagRules.parse
    private enum Field: Hashable { case name, persona, instructions }
    @FocusState private var focus: Field?

    var body: some View {
        NavigationStack {
            ThemedForm {
                Section {
                    HStack(spacing: 14) {
                        TextField("昵称，如：小研", text: $draft.name)
                            .focused($focus, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focus = .persona }
                    }
                    BotTagsField(text: $tagsText)
                }
                Section("新版机器人头像") {
                    RobotAvatarView(action: .idle, size: 88,
                                    color: BotAvatarColorPalette.appearanceColor(for: draft.color)?.swiftUIColor ?? Color(hex: draft.color))
                        .frame(maxWidth: .infinity).frame(height: 112)
                    BotAvatarColorPicker(selection: $draft.color)
                    Text("Bot 状态和情绪会驱动头像变化；当前可设置颜色，更多形状后续支持。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    TextField("例如：资深研究员，擅长资料检索与总结", text: $draft.persona, axis: .vertical)
                        .lineLimit(3...8)                         // 多行：回车换行；键盘工具栏「完成」收起
                        .focused($focus, equals: .persona)
                } header: {
                    Text("人设")
                } footer: {
                    Text("对其他 Bot 公开，协作时用来介绍自己。")
                }
                Section {
                    TextField("例如：先给结论，再给要点，不超过 200 字", text: $draft.instructions, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focus, equals: .instructions)
                } header: {
                    Text("自定义指令")
                } footer: {
                    Text("仅本 Bot 使用，不对其他 Bot 公开。")
                }
                Section {
                    Label("新 Bot 默认不开启工具、不参与委派。",
                          systemImage: "lock.shield")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                }
            }
            .navigationTitle("创建 Bot")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneButton { focus = nil }
            .interactiveDismissDisabled()   // 表单有未保存输入：只能点「取消」或「创建」退出
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { DismissToolbarButton(kind: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") { Task { await save() } }
                        .disabled(saving || draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var body = draft
        body.name = body.name.trimmingCharacters(in: .whitespaces)
        let cleaned = BotTagRules.parse(tagsText)
        if let message = cleaned.error {
            errorText = message
            return
        }
        body.tags = cleaned.tags
        do {
            _ = try await app.api.createBot(body)
            onCreated()
            dismiss()
        } catch {
            errorText = app.message(for: error)
        }
    }
}
