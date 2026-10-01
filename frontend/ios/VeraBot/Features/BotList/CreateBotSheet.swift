import SwiftUI
import VeraBotCore

struct CreateBotSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let onCreated: @MainActor () -> Void

    @State private var draft = BotCreate(name: "", avatar: "🤖", color: "#0f766e", persona: "", instructions: "")
    @State private var saving = false
    @State private var errorText: String?
    private enum Field: Hashable { case name, persona, instructions }
    @FocusState private var focus: Field?

    private let emojis = ["🤖", "🦊", "🐼", "🐱", "🦉", "🐧", "🦄", "🐙", "🌟", "🧠", "📚", "🔬", "💼", "🎨", "🍀", "☕"]
    private let colors = ["#0f766e", "#14b8a6", "#0369a1", "#334155", "#059669", "#d97706", "#e11d48", "#78716c"]

    var body: some View {
        NavigationStack {
            ThemedForm {
                Section {
                    HStack(spacing: 14) {
                        BotAvatar(emoji: draft.avatar, color: draft.color, size: 56)
                        TextField("昵称，如：小研", text: $draft.name)
                            .focused($focus, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focus = .persona }
                    }
                }
                Section("头像") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
                        ForEach(emojis, id: \.self) { e in
                            Text(e).font(.title2)
                                .frame(width: 34, height: 34)
                                .background(draft.avatar == e ? Color.brandSoft : .clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { draft.avatar = e }
                        }
                    }
                }
                Section("颜色") {
                    HStack {
                        ForEach(colors, id: \.self) { c in
                            Circle().fill(Color(hex: c)).frame(width: 28, height: 28)
                                .overlay(Circle().stroke(Color.primary, lineWidth: draft.color == c ? 2 : 0))
                                .onTapGesture { draft.color = c }
                        }
                    }
                }
                Section("人设 Persona") {
                    TextField("例如：资深研究员，擅长资料检索与总结", text: $draft.persona, axis: .vertical)
                        .lineLimit(3...8)                         // 多行：回车换行；键盘工具栏「完成」收起
                        .focused($focus, equals: .persona)
                }
                Section("自定义指令 Instructions") {
                    TextField("例如：先给结论，再给要点，不超过 200 字", text: $draft.instructions, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focus, equals: .instructions)
                }
                BotTagsSection(tags: $draft.tags)
                Section {
                    Label("新 Bot 默认最小权限（Least privilege）：不开启工具、不参与委派。创建后可在对话页右上角「Bot 设置」中开启。",
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
        let cleaned = BotTagRules.normalized(body.tags)
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
