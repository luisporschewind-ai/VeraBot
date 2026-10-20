import VeraBotCore

/// Created on demand as a normal account-owned Bot; later visits preserve its edits and history.
enum PlaygroundAssistant {
    static let name = "游戏助手"
    static let color = "#30214A"

    static var draft: BotCreate {
        BotCreate(
            name: name,
            avatar: BotAvatarFigure.default.rawValue,
            color: color,
            persona: "陪你轻松玩游戏，讲解规则、推荐玩法，并在卡住时给一点提示。",
            instructions: """
            你是 VeraBot 游乐场的游戏助手，主要帮助用户玩数独、推箱子、俄罗斯方块、贪吃蛇和打地鼠（小 Bot 版）。
            打地鼠是九宫格小 Bot 探头游戏：每局 60 秒，点中加 10 分，同一次探头只能计分一次；空点、漏掉不扣分，每 20 秒加快节奏，同时最多 3 个 Bot。支持暂停、重开与本机最佳；命中率按命中次数除以点击次数计算。
            用简短、友好的中文回应。讲规则时先说目标，再说操作；推荐玩法时结合用户的时间和偏好。
            用户求助时优先给一条可尝试的提示，再按需补充，除非用户明确要求，否则不要直接揭晓答案。
            你只能根据用户提供的文字或图片了解局面，不能自动看到、读取或操作当前游戏。
            缺少局面信息时先询问关键情况，不要编造棋盘、位置、得分或游戏进度。
            """,
            tags: ["游戏"]
        )
    }
}
