import SwiftUI
import VeraBotCore
import VeraBotTTS

/// 🔊 朗读按钮：用户消息与 Bot 回复共用，由设置页「语音播放」开关统一控制。
struct SpeakButton: View {
    let key: String
    let text: String
    @Environment(SpeechPlayer.self) private var player

    var body: some View {
        Button {
            player.toggle(id: key, text: text)
        } label: {
            Image(systemName: player.isSpeaking(key) ? "stop.circle.fill" : "speaker.wave.2.fill")
                .font(.footnote)
                .foregroundStyle(Color.brand)
                .padding(.horizontal, 8).padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(player.isSpeaking(key) ? "停止朗读" : "朗读")
    }
}
