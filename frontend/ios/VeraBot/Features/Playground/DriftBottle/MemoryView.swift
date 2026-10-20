import SwiftUI
import VeraBotCore
import VeraBotData

struct DriftBottleMemoryCardView: View {
    let memory: DriftBottleMemory
    var onEdit: (() -> Void)?
    var onRegenerate: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(memory.isBotGenerated ? "Bot 整理" : "按事实记录",
                      systemImage: memory.isBotGenerated ? "sparkles" : "text.quote")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.brandAccent)
                if memory.edited {
                    Text("你编辑过").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if onEdit != nil || onRegenerate != nil || onDelete != nil {
                    Menu {
                        if let onEdit { Button("编辑回忆卡", systemImage: "pencil", action: onEdit) }
                        if let onRegenerate { Button("重新整理", systemImage: "arrow.clockwise", action: onRegenerate) }
                        if let onDelete {
                            Button("只删除回忆卡", systemImage: "trash", role: .destructive, action: onDelete)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                    }
                }
            }
            Text(memory.title)
                .font(.headline)
                .foregroundStyle(Color.brandText)
            Text(memory.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !memory.ownerNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("你的一句话").font(.caption2).foregroundStyle(.tertiary)
                    Text(memory.ownerNote).font(.subheadline)
                }
                .padding(.top, 2)
            }
            Text("这张卡片只保存在漂流瓶里，不会自动写入普通聊天或长期记忆。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct DriftBottleMemoryEditSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let recordID: String
    let encounterID: Int
    let memory: DriftBottleMemory
    var onUpdated: (DriftBottleMemory?) -> Void

    @State private var title: String
    @State private var summary: String
    @State private var note: String
    @State private var working = false
    @State private var notice: String?

    init(recordID: String, encounterID: Int, memory: DriftBottleMemory,
         onUpdated: @escaping (DriftBottleMemory?) -> Void) {
        self.recordID = recordID
        self.encounterID = encounterID
        self.memory = memory
        self.onUpdated = onUpdated
        _title = State(initialValue: memory.title)
        _summary = State(initialValue: memory.summary)
        _note = State(initialValue: memory.ownerNote)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let notice {
                        DriftBottleNoticeBanner(text: notice) { self.notice = nil }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("一句话标题").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        TextField("标题", text: $title)
                            .themedFieldBackground()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("简短摘要").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        TextEditor(text: $summary)
                            .frame(minHeight: 120)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 12))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("你的一句话（可选）").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        TextField("这次相遇留给你的一句话", text: $note, axis: .vertical)
                            .lineLimit(1...3)
                            .themedFieldBackground()
                    }
                    Text("摘要由 Bot 根据本次实际交流整理；你可以改写或删掉整张卡片。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Button {
                        Task { await regenerate() }
                    } label: {
                        Label("让 Bot 重新整理", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(working)
                    Button(role: .destructive) {
                        Task { await deleteMemory() }
                    } label: {
                        Label("删除这张回忆卡", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(working)
                }
                .padding(20)
            }
            .themedPageBackground()
            .navigationTitle("编辑回忆卡")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(working || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var model: DriftBottleModel { app.driftBottle }

    private func save() async {
        working = true
        defer { working = false }
        let patch = DriftBottleMemoryPatch(title: title, summary: summary, ownerNote: note,
                                           expectedVersion: memory.version)
        if let updated = await model.patchMemory(recordID: recordID, patch: patch) {
            onUpdated(updated)
            dismiss()
        } else {
            notice = model.notice ?? "这次没有保存成功，内容还在。"
        }
    }

    private func regenerate() async {
        working = true
        defer { working = false }
        if let updated = await model.generateMemory(encounterID: encounterID) {
            title = updated.title
            summary = updated.summary
            onUpdated(updated)
            dismiss()
        } else {
            notice = model.notice ?? "这次没有整理成功，原来的卡片还在。"
        }
    }

    private func deleteMemory() async {
        working = true
        defer { working = false }
        if await model.deleteMemory(recordID: recordID) {
            onUpdated(nil)
            dismiss()
        } else {
            notice = model.notice ?? "这次没有删除成功。"
        }
    }
}

struct DriftBottleCompletionSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let record: DriftBottleRecord
    var onDone: (() -> Void)?

    @State private var memory: DriftBottleMemory?
    @State private var showingMemoryEdit = false
    @State private var working = false
    @State private var didTryGenerating = false

    init(record: DriftBottleRecord, onDone: (() -> Void)? = nil) {
        self.record = record
        self.onDone = onDone
        _memory = State(initialValue: record.memory)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("这次相遇收好了").font(.title3.bold()).foregroundStyle(Color.brandText)
                        Text("你们读到的东西、说过的话，和主人最后决定留下的文字，都收进了这条足迹。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let memory {
                        DriftBottleMemoryCardView(memory: memory, onEdit: {
                            showingMemoryEdit = true
                        }, onRegenerate: {
                            Task { await regenerate() }
                        })
                    } else if record.encounter != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("这张回忆卡还没有整理。")
                                .font(.subheadline)
                            Button {
                                Task { await regenerate() }
                            } label: {
                                Label("整理共同回忆", systemImage: "sparkles")
                            }
                            .buttonStyle(.bordered)
                            .disabled(working)
                        }
                        .padding(14)
                        .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 14))
                    }
                    if let encounter = record.encounter, encounter.botID != nil, !encounter.botDeleted {
                        Text("你仍可以从足迹里继续和 \(encounter.botName) 聊这次相遇；不会再向这封信追加公开留言。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        dismiss()
                        onDone?()
                    } label: {
                        Text("收好").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brandFill)
                }
                .padding(20)
            }
            .themedPageBackground()
            .navigationTitle("共同回忆")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showingMemoryEdit) {
            if let memory, let encounter = record.encounter {
                DriftBottleMemoryEditSheet(recordID: record.id, encounterID: encounter.id,
                                           memory: memory) { updated in
                    self.memory = updated
                }
            }
        }
        .task { await upgradeFactMemoryIfPossible() }
    }

    private var model: DriftBottleModel { app.driftBottle }

    /// Release always saves a factual fallback first. If the owner actually
    /// talked with the Bot, try once to turn it into a Bot-organized summary;
    /// a failure leaves the factual card in place and never blocks the memory.
    private func upgradeFactMemoryIfPossible() async {
        guard !didTryGenerating, let encounter = record.encounter,
              let current = memory, !current.isBotGenerated,
              record.turns.contains(where: { $0.kind == .chat }) else { return }
        didTryGenerating = true
        if let upgraded = await model.generateMemory(encounterID: encounter.id) {
            memory = upgraded
        }
    }

    private func regenerate() async {
        guard let encounter = record.encounter else { return }
        working = true
        defer { working = false }
        memory = await model.generateMemory(encounterID: encounter.id)
    }
}
