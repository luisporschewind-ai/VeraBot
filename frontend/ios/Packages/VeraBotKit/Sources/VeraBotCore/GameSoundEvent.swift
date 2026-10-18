/// 游戏音效事件。规则层（SnakeGame）用真实结果事件（吃食、结束、胜利）写入，
/// 视图层用输入事件（按键、开始/暂停/继续）。播放器把事件映射到对应短音频。
public enum GameSoundEvent: String, CaseIterable, Sendable {
    case keyPress
    case start
    case pause
    case resume
    case hardDrop
    case clearSingle
    case clearMulti
    case eat
    case gameOver
    case win
}
