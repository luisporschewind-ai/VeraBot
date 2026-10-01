import SwiftUI
import VeraBotCore
import VeraBotNetworking

/// 添加 / 编辑一条记忆（sheet）。保存前服务器再做敏感信息与注入检查，未通过时在表单底部显示服务器文案，不关闭 sheet。
struct MemoryEditView: View {
    enum Mode: Identifiable {
        case create(defaultBot: Bot?)
        case edit(Memory)
        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let m): return "edit-\(m.id)"
            }
        }
    }

    let mode: Mode
    let bots: [Bot]
    let onSaved: @MainActor () async -> Void

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var content = ""
    @State private var type: MemoryType = .preference
    @State private var scopeBotID: Int = 0          // 0 = 所有 Bot（global）；>0 = 仅该 Bot
    @State private var saving = false
    @State private var errorText: String?
    @State private var confirmDelete = false

    private static let maxChars = 200
    private var existing: Memory? { if case .edit(let m) = mode { return m } else { return nil } }
    private var trimmed: String { content.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ThemedForm {
                Section {
                    TextField("例如：我不吃香菜", text: $content, axis: .vertical)
                        .lineLimit(2...6)
                        .focused($focused)
                } header: {
                    Text("内容")
                } footer: {
                    Text("\(trimmed.count)/\(Self.maxChars)")
                        .foregroundStyle(trimmed.count > Self.maxChars ? .red : .secondary)
                }
                Section {
                    Picker("类型", selection: $type) {
                        ForEach(MemoryType.editable) { t in Text(t.title).tag(t) }
                    }
                    Picker("适用范围", selection: $scopeBotID) {
                        Text("所有 Bot").tag(0)
                        ForEach(bots) { b in Text("仅 \(b.name)").tag(b.id) }
                    }
                } footer: {
                    if let errorText {
                        Text(errorText).foregroundStyle(.red)
                    } else {
                        Text("健康、财务信息会加密保存；密码、验证码、证件号、卡号不会被记住。")
                    }
                }
                if let m = existing {
                    Section("信息") {
                        if m.sensitive, let s = m.sensitivity.title {
                            LabeledContent("敏感类别") { Label(s, systemImage: "lock") }
                        }
                        LabeledContent("来源", value: m.sourceTitle)
                        if let d = ListTimestamp.parse(m.confirmedAt ?? m.createdAt) {
                            LabeledContent("确认时间", value: d.formatted(date: .abbreviated, time: .shortened))
                        }
                        LabeledContent("最近使用",
                                       value: ListTimestamp.parse(m.lastUsedAt)?.formatted(date: .abbreviated, time: .shortened) ?? "尚未使用")
                        LabeledContent("使用次数", value: "\(m.useCount)")
                    }
                    Section {
                        Button("删除这条记忆", role: .destructive) { endEditing(); confirmDelete = true }
                            .confirmationDialog("删除这条记忆？", isPresented: $confirmDelete, titleVisibility: .visible) {
                                Button("删除", role: .destructive) { Task { await delete(m) } }
                                Button("取消", role: .cancel) {}
                            }
                    }
                }
            }
            .navigationTitle(existing == nil ? "添加记忆" : "编辑记忆")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    DismissToolbarButton(kind: .cancel) { endEditing(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { endEditing(); Task { await save() } }
                        .disabled(saving || trimmed.isEmpty || trimmed.count > Self.maxChars)
                }
            }
            .onAppear(perform: fill)
            .onDisappear(perform: endEditing)
        }
    }

    private func fill() {
        switch mode {
        case .create(let bot):
            scopeBotID = bot?.id ?? 0
        case .edit(let m):
            content = m.content
            type = MemoryType.editable.contains(m.type) ? m.type : .fact
            scopeBotID = m.scope == .global ? 0 : (m.botId ?? 0)
        }
    }

    private func endEditing() {
        focused = false
        Keyboard.dismiss()
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let scope: MemoryScope = scopeBotID == 0 ? .global : .bot
        let botID: Int? = scopeBotID == 0 ? nil : scopeBotID
        do {
            if let m = existing {
                let patch = MemoryPatch(content: trimmed == m.content ? nil : trimmed,
                                        type: type == m.type ? nil : type,
                                        scope: scope, botId: botID)
                _ = try await app.api.updateMemory(id: m.id, patch)
            } else {
                _ = try await app.api.createMemory(MemoryCreate(content: trimmed, type: type, scope: scope, botId: botID))
            }
            await onSaved()
            dismiss()
        } catch {
            errorText = app.message(for: error)
        }
    }

    private func delete(_ m: Memory) async {
        do {
            _ = try await app.api.deleteMemory(id: m.id)
            await onSaved()
            dismiss()
        } catch {
            errorText = app.message(for: error)
        }
    }
}
