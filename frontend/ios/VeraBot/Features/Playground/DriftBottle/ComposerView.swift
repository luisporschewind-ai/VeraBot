import SwiftUI
import VeraBotCore
import VeraBotData
import VeraBotNetworking

enum DriftBottleComposerMode: Hashable {
    case newBottle(botID: Int, botName: String, botAvatar: String, botColor: String)
    case message(encounter: DriftBottleEncounter)

    var isMessage: Bool {
        if case .message = self { return true }
        return false
    }

    var botName: String {
        switch self {
        case .newBottle(_, let name, _, _): name
        case .message(let encounter): encounter.botName
        }
    }

    var botAvatar: String {
        switch self {
        case .newBottle(_, _, let avatar, _): avatar
        case .message(let encounter): encounter.botAvatar
        }
    }

    var botColor: String {
        switch self {
        case .newBottle(_, _, _, let color): color
        case .message(let encounter): encounter.botColor
        }
    }

    var encounter: DriftBottleEncounter? {
        if case .message(let encounter) = self { return encounter }
        return nil
    }
}

struct DriftBottleComposerView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let mode: DriftBottleComposerMode
    var onPublished: (DriftBottleRecord?) -> Void

    @State private var text = ""
    @State private var authorship: DriftBottleAuthorship = .owner
    @State private var generated = false
    @State private var didLoadDraft = false
    @State private var showingPreview = false
    @State private var submitting = false
    @State private var localNotice: String?

    private var model: DriftBottleModel { app.driftBottle }

    private var characterCount: Int { DriftBottlePresentation.characterCount(text) }
    private var validation: String? { DriftBottlePresentation.validatePublic(text) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let notice = localNotice ?? model.notice {
                    DriftBottleNoticeBanner(text: notice) {
                        localNotice = nil
                        model.clearNotice()
                    }
                }
                editor
                authorshipPicker
                if generated {
                    Label("这是 Bot 起的草稿；只有你确认后才会公开。", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Button {
                        Task { await suggestDraft() }
                    } label: {
                        Label("让 Bot 帮我写", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isWorking || submitting || mode.encounter?.botDeleted == true)
                    Spacer()
                    Button {
                        showingPreview = true
                    } label: {
                        Label(mode.isMessage ? "预览留言" : "预览新瓶", systemImage: "eye")
                    }
                    .accessibilityIdentifier("drift.composer.preview")
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brandFill)
                    .disabled(validation != nil || model.isWorking || submitting)
                }
                boundaryCard
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .themedPageBackground()
        .navigationTitle(mode.isMessage ? "留下一句" : "写一个新瓶")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
        .task {
            guard !didLoadDraft else { return }
            didLoadDraft = true
            if let draft = model.draft(forNewBottle: !mode.isMessage,
                                       encounterID: mode.encounter?.id) {
                text = draft.text
                authorship = draft.authorship
                generated = draft.generated
            }
        }
        .onChange(of: text) { _, _ in
            guard didLoadDraft else { return }
            model.saveDraft(text: text, authorship: authorship, generated: generated,
                            forNewBottle: !mode.isMessage,
                            encounterID: mode.encounter?.id,
                            bottleID: mode.encounter?.bottleID)
        }
        .onChange(of: authorship) { _, _ in
            guard didLoadDraft else { return }
            model.saveDraft(text: text, authorship: authorship, generated: generated,
                            forNewBottle: !mode.isMessage,
                            encounterID: mode.encounter?.id,
                            bottleID: mode.encounter?.bottleID)
        }
        .sheet(isPresented: $showingPreview) {
            NavigationStack {
                DriftBottlePublicPreviewView(
                    preview: DriftBottlePresentation.publicPreview(
                        text: text, authorship: authorship, botName: mode.botName),
                    botAvatar: mode.botAvatar,
                    botColor: mode.botColor,
                    sequence: mode.encounter.map { "第 \($0.readLimit + 1) 条公开留言" },
                    submitting: submitting) {
                        Task { await publish() }
                    }
            }
            .presentationDetents([.large])
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            BotAvatar(emoji: mode.botAvatar, color: mode.botColor, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(mode.isMessage ? "和 \(mode.botName) 一起留下什么"
                     : "和 \(mode.botName) 一起写一封新瓶")
                    .font(.headline)
                    .foregroundStyle(Color.brandText)
                Text(mode.isMessage
                     ? "可以自己写、让 Bot 起草，或只把一瓶原信放回。"
                     : "新瓶会立刻进入共享池；发布后不能直接修改原文，但可以撤回。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $text)
                .accessibilityIdentifier("drift.composer.text")
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 190)
                .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("写下一段你愿意让陌生人读到的文字…")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
            HStack {
                if let validation, !text.isEmpty {
                    Text(validation)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("公开文字 1–\(DriftBottlePresentation.maxPublicLength) 个字符")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text("\(characterCount)/\(DriftBottlePresentation.maxPublicLength)")
                    .font(.caption2)
                    .foregroundStyle(characterCount > DriftBottlePresentation.maxPublicLength ? Color.red : Color.secondary)
            }
        }
    }

    private var authorshipPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            DriftBottleSectionTitle(title: "这条文字的署名",
                                    subtitle: "使用生成稿时不会自动标成主人亲笔")
            Picker("署名", selection: $authorship) {
                ForEach(DriftBottleAuthorship.allCases) { value in
                    Text(value.label).tag(value)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var boundaryCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
                .foregroundStyle(Color.brandAccent)
            Text(DriftBottlePresentation.publicBoundaryNotice + "\n" +
                 DriftBottlePresentation.publicAudienceNotice + "\n" +
                 DriftBottlePresentation.firstPublicNameNotice)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func suggestDraft() async {
        localNotice = nil
        let suggestion: String?
        if let encounter = mode.encounter {
            suggestion = await model.suggestEncounterDraft(text: text)
        } else if case .newBottle(let botID, _, _, _) = mode {
            suggestion = await model.suggestNewBottleDraft(botID: botID, text: text)
        } else {
            suggestion = nil
        }
        guard let suggestion else { return }
        text = suggestion
        authorship = DriftBottlePresentation.authorshipAfterGeneration(authorship)
        generated = true
        localNotice = "Bot 只给出了草稿。你可以修改、换署名，或放弃这次生成。"
    }

    private func publish() async {
        guard validation == nil, !submitting else { return }
        submitting = true
        defer { submitting = false }
        if let encounter = mode.encounter {
            let input = DriftBottleContributionInput(body: text, authorship: authorship)
            if let record = await model.release(contribution: input) {
                model.clearDraft(forNewBottle: false, encounterID: encounter.id)
                showingPreview = false
                onPublished(record)
                dismiss()
            } else {
                localNotice = model.notice ?? "这次放漂还没有确认结果，文字仍保留在编辑器里。"
                showingPreview = false
            }
        } else if case .newBottle(let botID, _, _, _) = mode {
            if await model.createBottle(botID: botID, text: text, authorship: authorship) != nil {
                model.clearDraft(forNewBottle: true)
                showingPreview = false
                onPublished(nil)
                dismiss()
            } else {
                localNotice = model.notice ?? "这次新瓶没有放漂成功，文字仍保留。"
                showingPreview = false
            }
        }
    }
}

struct DriftBottlePublicPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let preview: DriftBottlePublicPreview
    let botAvatar: String
    let botColor: String
    let sequence: String?
    let submitting: Bool
    var confirm: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: "eye")
                        .foregroundStyle(Color.brandAccent)
                    Text("确认要公开的文字")
                        .font(.headline)
                }
                VStack(alignment: .leading, spacing: 12) {
                    if let sequence {
                        Text(sequence).font(.caption.weight(.semibold)).foregroundStyle(Color.brandAccent)
                    }
                    Text(preview.text)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        DriftBottleBotSignature(name: preview.botName, avatar: botAvatar,
                                                color: botColor, size: 24,
                                                trailing: preview.authorshipLabel)
                        Spacer()
                        Text("\(preview.characterCount) 字符")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(16)
                .background(Color.sectionFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(Color.brandAccent)
                    Text(preview.boundaryNotice)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text(DriftBottlePresentation.firstPublicNameNotice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button {
                    confirm()
                } label: {
                    HStack {
                        if submitting { ProgressView().tint(.white) }
                        Text(submitting ? "正在放漂…" : "确认放漂")
                    }
                    .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("drift.preview.confirm")
                .buttonStyle(.borderedProminent)
                .tint(Color.brandFill)
                .disabled(submitting || !preview.isReadyToPublish)
                Button("返回修改") { dismiss() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
            .padding(20)
        }
        .themedPageBackground()
        .navigationTitle("公开预览")
        .navigationBarTitleDisplayMode(.inline)
    }
}
