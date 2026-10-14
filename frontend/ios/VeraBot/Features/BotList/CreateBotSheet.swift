import SwiftUI
import VeraBotCore

struct CreateBotSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    /// 打开创建页时的账号 Bot 数量；提交时做二次校验，防止重复触发绕过。
    let currentBotCount: Int
    let onCreated: @MainActor () -> Void

    @State private var draft = BotCreate(name: "", avatar: BotAvatarFigure.default.rawValue, color: BotAvatarColorPalette.defaultColor, persona: "", instructions: "")
    @State private var shape: BotAvatarFamilyShape = .standard
    @State private var saving = false
    @State private var errorText: String?
    @State private var tagsText = ""   // 「搜索, 查询, 调研」；保存时 BotTagRules.parse
    private enum Field: Hashable { case name, persona, instructions }
    @FocusState private var focus: Field?

    private var atAccountLimit: Bool { !BotProductLimits.canCreateBot(currentCount: currentBotCount) }

    var body: some View {
        NavigationStack {
            ThemedForm {
                RobotAvatarView(action: .idle, size: 88,
                                color: BotAvatarColorPalette.appearanceColor(for: draft.color)?.swiftUIColor ?? Color(hex: draft.color),
                                appearance: avatarAppearance)
                    .frame(maxWidth: .infinity).frame(height: 88)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
                Section {
                    TextField("昵称，如：小研", text: $draft.name)
                        .multilineTextAlignment(.center)
                        .focused($focus, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focus = .persona }
                    BotTagsField(text: $tagsText)
                }

                Section {
                    BotAvatarShapePicker(selection:$shape,color:draft.color)
                    BotAvatarColorPicker(selection: $draft.color)
                }
                Section {
                    TextField("例如：资深研究员，擅长资料检索与总结", text: $draft.persona, axis: .vertical)
                        .lineLimit(3...8)
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
                if atAccountLimit {
                    Text(BotProductLimits.accountLimitReachedMessage).foregroundStyle(.red)
                } else if let errorText {
                    Text(errorText).foregroundStyle(.red)
                }
            }
            .listSectionSpacing(12)
            .navigationTitle("创建 Bot")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneButton { focus = nil }
            .interactiveDismissDisabled()   // 表单有未保存输入：只能点「取消」或「创建」退出
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { DismissToolbarButton(kind: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") { Task { await save() } }
                        .disabled(saving || atAccountLimit || draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var avatarAppearance: BotAppearance {
        var value = BotAppearance.robotDefault
        value.familyShape = shape
        if let selected = BotAvatarColorPalette.appearanceColor(for:draft.color) { value.palette.body = selected }
        return value
    }

    private func save() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        // 提交时二次校验：防止菜单态与表单态之间重复触发绕过。
        guard BotProductLimits.canCreateBot(currentCount: currentBotCount) else {
            errorText = BotProductLimits.accountLimitReachedMessage
            return
        }
        var body = draft
        body.name = body.name.trimmingCharacters(in: .whitespaces)
        let cleaned = BotTagRules.parse(tagsText)
        if let message = cleaned.error {
            errorText = message
            return
        }
        body.tags = cleaned.tags
        do {
            body.appearance = try avatarAppearance.jsonValue()
            _ = try await app.api.createBot(body)
            onCreated()
            dismiss()
        } catch {
            errorText = app.message(for: error)
        }
    }
}
