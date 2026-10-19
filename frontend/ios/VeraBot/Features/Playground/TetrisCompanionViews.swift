import SwiftUI
import VeraBotCore

struct TetrisCompanionPresence: View {
    let model: TetrisCompanionModel
    var compact = false
    var activity: String? = nil
    let onTalk: () -> Void
    let onChoose: () -> Void
    let onQuiet: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            if let bot = model.selected {
                Text(message ?? " ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(compact ? 2 : 3)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 44 : 56)
                    .background {
                        if message != nil {
                            RoundedRectangle(cornerRadius: 12).fill(Color.brandSoft)
                        }
                    }
                    .accessibilityHidden(message == nil)

                Button(action: onTalk) {
                    ZStack {
                        Color.clear
                        LiveBotAvatar(botID: bot.id, emoji: bot.avatar, color: bot.color,
                                      hasAvatar: bot.hasAvatar, updatedAt: bot.avatarUpdatedAt,
                                      size: compact ? 56 : 72, action: model.action, animated: true,
                                      appearance: bot.supportedAppearance)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    .frame(width: compact ? 56 : 72, height: compact ? 56 : 72)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("和\(bot.name)说话，暂停游戏")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onTalk() }
                .accessibilityIdentifier("tetris-companion-avatar")

                Text(bot.name)
                    .font(.caption.bold())
                    .lineLimit(1)
                Text(activity ?? (model.quiet ? "安静陪着你" : "陪你玩"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 0) {
                    Button("聊聊", action: onTalk)
                        .font(.caption)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityLabel("暂停游戏，和\(bot.name)聊聊")
                    Menu {
                        Button("换个伙伴", action: onChoose)
                        Button(model.quiet ? "恢复主动回应" : "先安静陪我", action: onQuiet)
                        Button("暂停聊聊", action: onTalk)
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("陪玩选项")
                    .accessibilityIdentifier("tetris-companion-options")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.brand)
            } else {
                Image(systemName: "person.crop.circle.badge.plus").font(.title2).foregroundStyle(Color.brand)
                Text(model.loading ? "正在邀请伙伴…" : (model.loadError ?? "先到助理页创建一个 Bot，就能邀请它陪玩。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                if model.loadError != nil {
                    Button("重试", action: onRetry).font(.caption).frame(minHeight: 44)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var message: String? {
        if let error = model.error { return error }
        guard !model.quiet else { return nil }
        if !model.text.isEmpty { return model.text }
        return model.requesting ? "正在回应…" : nil
    }
}

struct TetrisCompanionConversation: View {
    @Bindable var model: TetrisCompanionModel
    let summary: String
    let onSend: (String) -> Void
    let onContinue: () -> Void
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text(summary).font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal).padding(.top, 8)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if model.turns.isEmpty {
                            Text("游戏已经暂停。可以聊聊，也可以一起看看现在的局面。")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        ForEach(model.turns) { turn in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(turn.role == "user" ? "你" : (model.selected?.name ?? "Bot"))
                                    .font(.caption.bold()).foregroundStyle(Color.brand)
                                Text(turn.content).font(.subheadline).textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(turn.role == "user" ? Color.sectionFill : Color.brandSoft,
                                        in: RoundedRectangle(cornerRadius: 14))
                        }
                        if model.requesting { ProgressView("正在听你说…").font(.caption) }
                        if let error = model.error { Text(error).font(.caption).foregroundStyle(.secondary) }
                    }.padding()
                }
                HStack(spacing: 10) {
                    Button("陪我聊聊") { onSend("陪我聊聊，轻松一点。") }
                    Button("一起看看局面") { onSend("一起看看当前局面，解释一下现在的情况，不要直接替我决定怎么放。") }
                }.font(.caption).buttonStyle(.bordered).disabled(model.requesting)
                HStack {
                    TextField("和伙伴说句话", text: $draft, axis: .vertical)
                        .lineLimit(1...3).textFieldStyle(.roundedBorder)
                        .onChange(of: draft) { _, value in if value.count > 1000 { draft = String(value.prefix(1000)) } }
                    Button("发送") {
                        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty else { return }
                        draft = ""
                        onSend(value)
                    }.disabled(model.requesting || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(.horizontal).padding(.bottom, 12)
            }
            .themedPageBackground()
            .navigationTitle(model.selected.map { "和\($0.name)聊聊" } ?? "陪玩")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("回到游戏", action: onContinue) } }
        }
    }
}
