import Foundation

enum NoticePlacement: String, CaseIterable, Identifiable {
    case banner, inline, empty, field, confirmation, system
    var id: String { rawValue }
    var title: String {
        switch self {
        case .banner: "顶部横幅"
        case .inline: "页面状态"
        case .empty: "空白页"
        case .field: "输入校验"
        case .confirmation: "确认操作"
        case .system: "系统通知"
        }
    }
    var guidance: String {
        switch self {
        case .banner: "短暂反馈，不打断操作；不承担持续状态。"
        case .inline: "状态留在相关内容附近，直到操作完成或问题解除。"
        case .empty: "页面无法展示内容时提供解释和下一步。"
        case .field: "问题紧邻输入项，不让用户靠短暂横幅寻找错误。"
        case .confirmation: "涉及删除、发送、权限等决定，保留明确确认；横幅只试验结果反馈。"
        case .system: "交给系统通知机制；实验室只做视觉示意，不申请权限、不发送通知。"
        }
    }
}

struct NoticeScenario: Identifiable {
    let id: String
    let group: String
    let title: String
    let message: String
    let detail: String
    let tone: BotNoticeTone
    let avatar: BotAvatarState
    let current: String
    let proposed: NoticePlacement
    let source: String
    var notice: BotNotice {
        BotNotice(title: message, detail: detail, tone: tone, avatar: avatar,
                  actionTitle: (tone == .failure || (tone == .warning && group == "启动与连接"))
                    && (proposed == .inline || proposed == .empty) ? "重试" : nil,
                  duration: proposed == .banner ? 3 : nil)
    }
}

enum NoticeScenarioCatalog {
    /// Existing client flows; suggested copy and placements are experiments, not migrated behavior.
    static let all: [NoticeScenario] = groups.flatMap { group in
        group.items.enumerated().map { index, item in
            NoticeScenario(id: "\(group.id).\(index)", group: group.title, title: item.title,
                           message: item.message, detail: item.detail, tone: item.tone,
                           avatar: item.avatar ?? item.tone.avatar, current: item.current,
                           proposed: item.placement, source: item.source)
        }
    }
    static var groupTitles: [String] { groups.map(\.title) }

    private struct Item {
        let title: String
        let message: String
        let detail: String
        let tone: BotNoticeTone
        let placement: NoticePlacement
        let current: String
        let source: String
        let avatar: BotAvatarState?
        init(_ title: String, _ message: String, _ tone: BotNoticeTone, _ placement: NoticePlacement,
             _ current: String, _ source: String, detail: String = "", avatar: BotAvatarState? = nil) {
            self.title = title; self.message = message; self.tone = tone; self.placement = placement
            self.current = current; self.source = source; self.detail = detail; self.avatar = avatar
        }
    }
    private struct Group {
        let id: String
        let title: String
        let items: [Item]
    }

    private static let groups: [Group] = [
        Group(id: "connection", title: "启动与连接", items: [
            Item("启动招呼", "你的 Bot 已准备好", .information, .empty, "Bot 欢迎动画", "Core/UI/BotWelcomeView.swift", avatar: .send),
            Item("首次加载", "正在连接你的 Bot…", .progress, .empty, "Bot 等待页", "Core/UI/BotConnectionView.swift", avatar: .waiting),
            Item("设备离线", "网络暂时断开", .warning, .inline, "Bot 连接页 / 首页卡片", "Core/UI/BotConnectionView.swift", detail: "连上网络后再试一次"),
            Item("连接超时", "连接有些慢", .warning, .inline, "Bot 连接页 / 首页卡片", "Core/UI/BotConnectionView.swift", detail: "可以稍后重试"),
            Item("服务不可达", "暂时连不上 Bot", .failure, .inline, "Bot 连接页 / 首页卡片", "Core/UI/BotConnectionView.swift", avatar: .error),
            Item("服务暂不可用", "Bot 暂时无法连接", .failure, .inline, "Bot 连接页 / 首页卡片", "Core/UI/BotConnectionView.swift", avatar: .error),
            Item("重新连接中", "正在重新连接…", .progress, .inline, "Bot 等待状态 + 禁用重试", "Core/UI/BotConnectionView.swift", avatar: .waiting),
            Item("会话失效", "请重新登录", .warning, .inline, "会话处理 / 页面错误文字", "App/AppState.swift"),
            Item("链接目标已不存在", "这条内容已不存在", .information, .banner, "全局「提示」弹窗", "App/VeraBotApp.swift")
        ]),
        Group(id: "auth", title: "登录与账号", items: [
            Item("登录 / 注册中", "正在登录…", .progress, .inline, "按钮加载状态", "Features/Auth/LoginView.swift", avatar: .waiting),
            Item("账号输入不完整", "请检查账号信息", .warning, .field, "按钮校验 / 错误文字", "Features/Auth/LoginView.swift"),
            Item("登录 / 注册失败", "暂时无法登录", .failure, .inline, "错误文字 / Bot 连接状态", "Features/Auth/LoginView.swift"),
            Item("登录 / 注册完成", "欢迎回来", .success, .banner, "进入主页面，无统一成功提示", "Features/Auth/LoginView.swift", avatar: .smile),
            Item("验证码发送中", "正在发送验证码…", .progress, .inline, "按钮进度", "Features/Auth/LoginView.swift", avatar: .send),
            Item("验证码已发送", "验证码已发送", .success, .banner, "页面 infoText", "Features/Auth/LoginView.swift", detail: "请查看邮箱"),
            Item("验证码发送失败", "验证码未能发送", .failure, .inline, "页面错误文字", "Features/Auth/LoginView.swift"),
            Item("清除登录信息失败", "暂时无法清除登录信息", .failure, .inline, "页面错误文字", "Features/Auth/LoginView.swift"),
            Item("昵称校验", "昵称需要 1–32 个字", .warning, .field, "弹窗输入 / 页面错误文字", "Features/Settings/UserProfileEditor.swift"),
            Item("昵称 / 头像保存中", "正在保存个人资料…", .progress, .inline, "按钮进度", "Features/Settings/UserProfileEditor.swift"),
            Item("昵称 / 头像保存成功", "个人资料已更新", .success, .banner, "页面更新，无统一成功提示", "Features/Settings/UserProfileEditor.swift"),
            Item("昵称 / 头像保存失败", "个人资料未能保存", .failure, .inline, "页面错误文字", "Features/Settings/UserProfileEditor.swift"),
            Item("头像读取 / 处理失败", "这张照片暂时无法使用", .failure, .inline, "页面错误文字", "Features/Settings/UserProfileEditor.swift"),
            Item("验证邮箱", "请验证你的邮箱", .confirmation, .confirmation, "系统输入弹窗", "Features/Settings/UserProfileEditor.swift"),
            Item("验证码格式错误", "请输入 6 位数字验证码", .warning, .field, "页面错误文字", "Features/Settings/UserProfileEditor.swift"),
            Item("邮箱验证完成", "邮箱已验证", .success, .banner, "资料刷新", "Features/Settings/UserProfileEditor.swift"),
            Item("邮箱验证失败", "邮箱验证未完成", .failure, .inline, "页面错误文字", "Features/Settings/UserProfileEditor.swift"),
            Item("退出登录确认", "确定退出登录？", .confirmation, .confirmation, "系统确认面板", "Features/Settings/SettingsView.swift")
        ]),
        Group(id: "bots", title: "Bot 管理", items: [
            Item("没有 Bot", "还没有 Bot 伙伴", .information, .empty, "系统空状态", "Features/BotList/BotListView.swift", detail: "创建第一位助理吧"),
            Item("搜索没有结果", "没有找到匹配的 Bot", .information, .empty, "系统空状态", "Features/BotList/BotListView.swift", avatar: .inspect),
            Item("Bot 列表读取失败", "暂时无法读取 Bot 列表", .failure, .inline, "Bot 连接卡片 / 错误文字", "Features/BotList/BotListView.swift"),
            Item("创建信息校验", "请检查 Bot 的名称和设置", .warning, .field, "表单校验文字", "Features/BotList/CreateBotSheet.swift"),
            Item("创建 Bot 中", "正在创建 Bot…", .progress, .inline, "禁用提交按钮", "Features/BotList/CreateBotSheet.swift"),
            Item("Bot 创建成功", "新伙伴已加入", .success, .banner, "关闭创建页并刷新", "Features/BotList/CreateBotSheet.swift"),
            Item("Bot 创建失败", "Bot 未能创建", .failure, .inline, "表单错误文字", "Features/BotList/CreateBotSheet.swift"),
            Item("置顶 / 取消置顶成功", "Bot 排序已更新", .success, .banner, "列表排序更新", "Features/BotList/BotListView.swift"),
            Item("置顶失败", "排序未能更新", .failure, .banner, "列表错误文字", "Features/BotList/BotListView.swift"),
            Item("删除 Bot 确认", "确定删除这位 Bot？", .confirmation, .confirmation, "系统确认面板", "Packages/VeraBotKit/Sources/VeraBotCore/BotDeletion.swift", detail: "相关数据的处理以原有说明为准"),
            Item("Bot 删除成功", "Bot 已删除", .success, .banner, "列表更新 / 返回列表", "Features/Chat/ChatView.swift"),
            Item("Bot 删除失败", "Bot 未能删除", .failure, .inline, "页面错误文字", "Features/Chat/ChatView.swift"),
            Item("Bot 昵称 / 标签输入", "请检查名称和标签", .warning, .field, "系统输入弹窗 / 无法修改弹窗", "Features/BotInfo/BotEditView.swift"),
            Item("Bot 设置保存中", "正在保存 Bot 设置…", .progress, .inline, "保存按钮禁用", "Features/BotInfo/BotEditView.swift"),
            Item("Bot 设置保存成功", "Bot 设置已保存", .success, .banner, "页面更新 / 返回", "Features/BotInfo/BotEditView.swift"),
            Item("Bot 设置保存失败", "Bot 设置未能保存", .failure, .inline, "页面错误文字", "Features/BotInfo/BotEditView.swift"),
            Item("Bot 头像读取失败", "这张照片暂时无法读取", .failure, .inline, "页面错误文字", "Features/BotInfo/BotEditView.swift"),
            Item("Bot 设置部分保存", "设置已保存，头像未更新", .warning, .inline, "部分成功错误文字", "Features/BotInfo/BotEditView.swift", detail: "可以单独重试头像更新"),
            Item("协作记录为空", "还没有协作记录", .information, .empty, "系统空状态", "Features/BotInfo/DelegationLogView.swift"),
            Item("协作记录读取失败", "协作记录暂时无法读取", .failure, .inline, "页面错误文字", "Features/BotInfo/DelegationLogView.swift")
        ]),
        Group(id: "chat", title: "对话与执行状态", items: [
            Item("读取消息失败", "消息暂时无法读取", .failure, .inline, "消息列表错误文字", "Features/Chat/ChatViewModel.swift"),
            Item("输入中", "正在听你说", .information, .inline, "输入栏 / Bot 状态", "Features/Settings/BotAvatarState.swift", avatar: .input),
            Item("正在召回记忆", "正在回想相关记忆…", .progress, .inline, "导航栏 Bot 状态", "Features/Settings/BotAvatarState.swift", avatar: .recalling),
            Item("思考中", "正在想一想…", .progress, .inline, "导航栏 Bot 状态", "Features/Settings/BotAvatarState.swift", avatar: .thinking),
            Item("工具执行中", "正在处理…", .progress, .inline, "导航栏 Bot 状态 / 工具卡片", "Features/Settings/BotAvatarState.swift", avatar: .working),
            Item("委派中", "正在请伙伴协助…", .progress, .inline, "导航栏 Bot 状态 / Trace", "Features/Settings/BotAvatarState.swift", avatar: .delegating),
            Item("回复中", "正在回复…", .progress, .inline, "流式消息 / Bot 状态", "Features/Settings/BotAvatarState.swift", avatar: .replying),
            Item("等待工具确认", "这一步需要你确认", .confirmation, .confirmation, "对话内工具确认卡片", "Features/Chat/ToolConfirmationCard.swift"),
            Item("执行受阻", "这一步暂时无法继续", .warning, .inline, "导航栏 Bot 状态", "Features/Settings/BotAvatarState.swift", avatar: .blocked),
            Item("任务完成", "处理完成", .success, .banner, "Bot 终态 / 消息结果", "Features/Settings/BotAvatarState.swift"),
            Item("回复 / 流式连接失败", "这次回复未能完成", .failure, .inline, "消息错误文字 / Bot 终态", "Features/Chat/ChatViewModel.swift", avatar: .error),
            Item("额度不足 / 请求受限", "暂时无法继续对话", .warning, .inline, "429 错误文字", "Features/Chat/ChatViewModel.swift", detail: "请查看用量，或稍后再试"),
            Item("停止生成", "已停止本次回复", .information, .banner, "停止按钮 / 消息状态", "Features/Chat/ChatViewModel.swift"),
            Item("复制消息 / 链接", "已复制", .success, .banner, "写入剪贴板，无统一成功提示", "Core/UI/MessageContentView.swift"),
            Item("删除消息确认", "确定删除这条消息？", .confirmation, .confirmation, "系统确认面板", "Features/Chat/MessageRow.swift", detail: "已记住的内容不受影响"),
            Item("消息删除成功", "消息已删除", .success, .banner, "消息列表更新", "Features/Chat/ChatViewModel.swift"),
            Item("消息删除失败", "消息未能删除", .failure, .inline, "页面错误文字", "Features/Chat/ChatViewModel.swift"),
            Item("清空对话确认", "确定清空全部对话？", .confirmation, .confirmation, "系统确认面板", "Features/Chat/ChatView.swift"),
            Item("清空对话成功", "对话已清空", .success, .banner, "消息列表更新", "Features/Chat/ChatViewModel.swift"),
            Item("清空对话失败", "对话未能清空", .failure, .inline, "页面错误文字", "Features/Chat/ChatViewModel.swift"),
            Item("反馈原因选择", "哪里需要改进？", .confirmation, .confirmation, "系统选择面板", "Features/Chat/MessageRow.swift"),
            Item("反馈提交结果", "反馈已记录", .success, .banner, "消息反馈状态", "Features/Chat/ChatViewModel.swift"),
            Item("反馈提交 / 撤销失败", "反馈暂时未能更新", .failure, .inline, "页面错误文字", "Features/Chat/ChatViewModel.swift"),
            Item("候选记忆轻提醒", "有几件事等待你确认", .information, .inline, "输入栏上方查看记忆胶囊", "Features/Chat/ChatView.swift", avatar: .recalling)
        ]),
        Group(id: "attachments", title: "附件与语音", items: [
            Item("附件准备中", "正在准备附件…", .progress, .inline, "附件缩略卡片进度", "Features/Chat/ComposerAttachmentModel.swift", avatar: .waiting),
            Item("附件上传中", "正在上传附件…", .progress, .inline, "附件缩略卡片进度", "Features/Chat/ComposerAttachmentModel.swift"),
            Item("附件上传完成", "附件已准备好", .success, .inline, "附件 ready 状态", "Features/Chat/ComposerAttachmentModel.swift"),
            Item("附件上传失败", "附件未能上传", .failure, .inline, "附件错误 + 重试", "Features/Chat/AttachmentViews.swift"),
            Item("附件读取 / 图片处理失败", "这个附件暂时无法读取", .failure, .inline, "附件错误文字", "Services/Attachments/ImagePreparer.swift"),
            Item("文件大小超过限制", "文件需要小于 10 MB", .warning, .inline, "附件错误文字", "Features/Chat/ComposerAttachmentModel.swift"),
            Item("文件格式不支持", "暂不支持这个文件格式", .warning, .inline, "附件错误文字", "Features/Chat/ComposerAttachmentModel.swift", detail: "支持 PDF、TXT、MD、CSV、DOCX 和 XLSX"),
            Item("下载 / 预览附件中", "正在打开附件…", .progress, .inline, "附件气泡进度", "Features/Chat/AttachmentViews.swift", avatar: .waiting),
            Item("下载 / 预览附件失败", "附件暂时无法打开", .failure, .inline, "附件气泡错误", "Features/Chat/AttachmentViews.swift"),
            Item("相机权限关闭", "需要允许使用相机", .warning, .confirmation, "系统权限说明弹窗", "Features/Chat/ChatView.swift", detail: "可前往系统设置开启"),
            Item("麦克风 / 识别权限关闭", "需要允许使用麦克风和语音识别", .warning, .inline, "输入栏错误文字", "Services/Speech/SpeechInput.swift"),
            Item("正在听语音", "正在听你说…", .progress, .inline, "输入栏录音状态", "Services/Speech/SpeechInput.swift", avatar: .input),
            Item("识别不可用 / 无输入", "暂时无法识别语音", .failure, .inline, "输入栏错误文字", "Services/Speech/SpeechInput.swift"),
            Item("语音播放中", "正在朗读…", .progress, .inline, "播放按钮状态", "Features/Chat/MessageRow.swift", avatar: .replying),
            Item("云端语音暂不可用", "云端朗读尚未开放", .information, .inline, "设置页禁用云端引擎选项", "Features/Settings/SettingsView.swift")
        ]),
        Group(id: "actions", title: "工具确认与建议", items: [
            Item("工具风险说明", "请确认这次操作", .confirmation, .confirmation, "冻结参数 + 风险说明卡片", "Features/Chat/ToolConfirmationCard.swift"),
            Item("工具参数不可读", "暂时无法读取操作详情", .warning, .inline, "工具卡片警告文字", "Features/Chat/ToolConfirmationCard.swift"),
            Item("工具操作执行成功", "操作已完成", .success, .inline, "工具卡片 done 状态", "Features/Chat/ToolConfirmationCard.swift"),
            Item("工具操作取消", "操作已取消", .information, .inline, "工具卡片 cancelled 状态", "Features/Chat/ToolConfirmationCard.swift"),
            Item("工具操作过期", "这次操作已过期", .warning, .inline, "工具卡片 expired 状态", "Features/Chat/ToolConfirmationCard.swift"),
            Item("工具操作失败 / 结果未知", "操作结果暂时无法确认", .failure, .inline, "工具卡片 failed / unknown 状态", "Features/Chat/ToolConfirmationCard.swift"),
            Item("确认冲突 / 状态已更新", "这次操作的状态已变化", .warning, .inline, "409 / 410 后刷新确认卡片", "Features/Chat/ChatViewModel.swift"),
            Item("规律提醒 / 委派建议", "要采用这个建议吗？", .confirmation, .confirmation, "对话内建议卡片", "Features/Chat/MessageRow.swift"),
            Item("建议处理失败", "建议暂时未能处理", .failure, .inline, "建议卡片错误文字", "Features/Chat/MessageRow.swift"),
            Item("建议已接受 / 暂不采用", "建议已处理", .success, .banner, "建议卡片更新", "Features/Chat/ChatViewModel.swift")
        ]),
        Group(id: "memory", title: "记忆与回顾", items: [
            Item("记忆列表为空", "还没有记忆", .information, .empty, "系统空状态", "Features/Memory/MemoryListView.swift", avatar: .recalling),
            Item("记忆引用不可见", "没有可显示的记忆", .information, .empty, "系统空状态", "Features/Memory/MemoryReferencesView.swift"),
            Item("记忆读取失败", "记忆暂时无法读取", .failure, .inline, "页面错误文字", "Features/Memory/MemoryListView.swift"),
            Item("待确认记忆", "这件事要记住吗？", .confirmation, .confirmation, "记忆候选卡片", "Features/Memory/MemoryProposalCard.swift"),
            Item("编辑后记住", "确认记住修改后的内容？", .confirmation, .confirmation, "系统输入弹窗", "Features/Memory/MemoryProposalCard.swift"),
            Item("记忆确认成功", "已记住", .success, .banner, "记忆状态更新 + 触感", "Features/Chat/ChatView.swift"),
            Item("记忆忽略 / 忘掉成功", "已处理这条记忆", .success, .banner, "卡片 / 列表更新", "Features/Memory/MemoryListView.swift"),
            Item("记忆处理失败", "这条记忆暂时未能处理", .failure, .inline, "页面 / 卡片错误", "Features/Chat/ChatViewModel.swift"),
            Item("记忆已删除 / 已变化", "这条记忆已变化", .warning, .inline, "404 / 409 / 410 后刷新卡片", "Features/Chat/ChatViewModel.swift"),
            Item("记忆保存成功", "记忆已保存", .success, .banner, "关闭编辑页", "Features/Memory/MemoryEditView.swift"),
            Item("记忆保存失败", "记忆未能保存", .failure, .inline, "编辑页错误文字", "Features/Memory/MemoryEditView.swift"),
            Item("删除 / 清空记忆确认", "确定删除这些记忆？", .confirmation, .confirmation, "系统确认面板", "Features/Memory/MemoryListView.swift"),
            Item("记忆设置保存失败", "记忆设置未能保存", .failure, .inline, "设置错误文字", "Features/Memory/MemorySettingsSection.swift"),
            Item("记忆说明", "关于 Bot 的记忆", .information, .confirmation, "系统说明弹窗", "Features/Memory/MemoryListView.swift"),
            Item("月度回顾整理 / 生成中", "正在整理本月回顾…", .progress, .inline, "页面进度 / pending 状态", "Features/Memory/MemoryMonthlyReviewView.swift", avatar: .recalling),
            Item("月度回顾无法生成", "回顾暂时未能生成", .failure, .inline, "unavailable 状态 + 重试", "Features/Memory/MemoryMonthlyReviewView.swift"),
            Item("本月没有新增记忆", "本月没有新增记忆", .information, .inline, "分组内说明文字", "Features/Memory/MemoryMonthlyReviewView.swift"),
            Item("回顾详情记忆删除失败", "记忆暂时未能删除", .failure, .inline, "详情错误文字", "Features/Memory/MemoryMonthlyReviewView.swift")
        ]),
        Group(id: "reminders", title: "提醒与通知", items: [
            Item("提醒列表为空", "还没有提醒", .information, .empty, "系统空状态", "Features/Reminders/RemindersView.swift"),
            Item("通知收件箱为空", "暂时没有新通知", .information, .empty, "空列表", "Features/Reminders/InboxView.swift"),
            Item("通知收件箱读取失败", "通知暂时无法读取", .failure, .inline, "页面错误文字", "Features/Reminders/InboxView.swift"),
            Item("提醒同步失败", "提醒暂时未能同步", .failure, .inline, "页面错误文字 / 同步状态", "App/AppState+Reminders.swift"),
            Item("提醒保存中", "正在保存提醒…", .progress, .inline, "禁用保存按钮", "Features/Reminders/ReminderEditorView.swift"),
            Item("提醒保存成功", "提醒已保存", .success, .banner, "关闭编辑页并刷新", "Features/Reminders/ReminderEditorView.swift"),
            Item("提醒保存失败", "提醒未能保存", .failure, .inline, "编辑页错误文字", "Features/Reminders/ReminderEditorView.swift"),
            Item("提醒被其他地方修改", "这条提醒已在别处修改", .warning, .confirmation, "重新加载确认弹窗", "Features/Reminders/ReminderEditorView.swift"),
            Item("删除提醒 / 重复系列确认", "要删除哪一部分提醒？", .confirmation, .confirmation, "单次 / 整个系列确认面板", "Features/Reminders/ReminderEditorView.swift"),
            Item("完成 / 稍后 / 删除提醒结果", "提醒已更新", .success, .banner, "列表更新 / 本机操作队列", "Features/Reminders/RemindersView.swift"),
            Item("提醒操作失败", "提醒暂时未能更新", .failure, .inline, "页面错误文字", "Features/Reminders/RemindersView.swift"),
            Item("通知到点", "到提醒时间了", .information, .system, "系统通知横幅、声音、列表", "Services/Notifications/NotificationCoordinator.swift", avatar: .wake),
            Item("通知权限关闭", "通知权限已关闭", .warning, .confirmation, "前往设置说明弹窗", "Features/Settings/NotificationSettingsView.swift"),
            Item("通知设置保存失败", "通知设置未能保存", .failure, .inline, "设置页错误文字", "Features/Settings/NotificationSettingsView.swift"),
            Item("通知链接目标缺失", "这条提醒已不存在", .information, .banner, "missingNotice 系统弹窗", "App/AppState+Reminders.swift")
        ]),
        Group(id: "plugins", title: "插件与连接账号", items: [
            Item("插件列表 / 详情读取失败", "插件暂时无法读取", .failure, .inline, "页面错误文字", "Features/Plugins/PluginListView.swift"),
            Item("插件安装 / 卸载中", "正在更新插件…", .progress, .inline, "busy 按钮状态", "Features/Plugins/PluginDetailView.swift"),
            Item("插件安装成功", "插件已安装", .success, .banner, "插件详情刷新", "Features/Plugins/PluginCatalogView.swift"),
            Item("插件安装 / 卸载失败", "插件暂时未能更新", .failure, .inline, "页面错误文字", "Features/Plugins/PluginDetailView.swift"),
            Item("卸载插件确认", "确定卸载这个插件？", .confirmation, .confirmation, "系统确认面板", "Features/Plugins/PluginDetailView.swift"),
            Item("数据使用同意", "请确认数据使用说明", .confirmation, .confirmation, "同意说明 / 提示弹窗", "Features/Plugins/PluginDetailView.swift"),
            Item("未同意 / 需要追加权限", "连接前需要你的授权", .warning, .inline, "连接区域提示文字", "Features/Plugins/PluginDetailView.swift"),
            Item("连接 Google 中", "正在连接账号…", .progress, .inline, "授权浏览器 / busy 状态", "Features/Plugins/PluginDetailView.swift", avatar: .waiting),
            Item("账号连接成功", "账号已连接", .success, .banner, "连接状态刷新", "Features/Plugins/PluginDetailView.swift"),
            Item("Google 登录取消", "已取消账号连接", .information, .banner, "页面错误文字", "Features/Plugins/PluginDetailView.swift"),
            Item("Google 回调 / 连接失败", "账号暂时未能连接", .failure, .inline, "页面错误文字", "Features/Plugins/PluginDetailView.swift"),
            Item("令牌保存失败", "连接信息未能保存", .failure, .inline, "令牌输入页错误，保留暂存", "Features/Plugins/ConnectorTokenSheet.swift"),
            Item("断开账号确认", "确定断开这个账号？", .confirmation, .confirmation, "系统确认面板", "Features/Plugins/PluginDetailView.swift"),
            Item("断开账号成功", "账号已断开连接", .success, .banner, "详情刷新", "Features/Plugins/PluginDetailView.swift"),
            Item("断开账号失败", "账号暂时未能断开", .failure, .inline, "页面错误文字", "Features/Plugins/PluginDetailView.swift"),
            Item("插件工具超出数量限制", "这个 Bot 的工具已达上限", .warning, .inline, "工具开关错误文字", "Features/Plugins/PluginDetailView.swift"),
            Item("工具权限保存成功", "工具权限已更新", .success, .banner, "工具开关刷新", "Features/Plugins/PluginDetailView.swift"),
            Item("工具权限保存失败", "工具权限暂时未能保存", .failure, .inline, "页面错误文字", "Features/Plugins/PluginDetailView.swift"),
            Item("没有插件工具 / 没有启用 Bot", "还没有可用的插件工具", .information, .empty, "空状态文字", "Features/Plugins/PluginDetailView.swift")
        ]),
        Group(id: "play", title: "游乐场与旅行", items: [
            Item("寻找游戏 / 旅行伙伴", "正在找你的伙伴…", .progress, .inline, "页面进度", "Features/Playground/WorldViews.swift", avatar: .waiting),
            Item("没有 Bot 伙伴", "还没有 Bot 伙伴", .information, .empty, "系统空状态", "Features/Playground/BotTravelViews.swift"),
            Item("伙伴列表读取失败", "伙伴暂时无法连接", .failure, .inline, "空状态 / 错误文字", "Features/Playground/WorldViews.swift"),
            Item("游戏助手打开失败", "暂时无法打开游戏助手", .failure, .confirmation, "系统错误弹窗", "Features/Playground/WorldViews.swift"),
            Item("完成一局 / 一关", "这一局完成了", .success, .confirmation, "系统完成弹窗", "Features/Playground/MiniGameViews.swift", avatar: .smile),
            Item("全部通关", "全部通关了", .success, .confirmation, "系统通关弹窗", "Features/Playground/MiniGameViews.swift", avatar: .starEyes),
            Item("陪玩正在听 / 回复中", "伙伴正在回应…", .progress, .inline, "陪玩面板进度", "Features/Playground/TetrisCompanionViews.swift", avatar: .replying),
            Item("陪玩回应失败", "伙伴暂时没连上", .warning, .inline, "陪玩面板错误文字", "Features/Playground/TetrisCompanionModel.swift", detail: "你仍可以继续玩"),
            Item("旅行出发", "伙伴出发了", .success, .banner, "旅行状态卡片", "Features/Playground/BotTravelViews.swift", avatar: .send),
            Item("旅行进行中", "伙伴正在旅行", .progress, .inline, "进度 / 倒计时", "Features/Playground/BotTravelViews.swift"),
            Item("旅行归来", "伙伴回来了", .success, .inline, "旅行完成 / 纪念卡片", "Features/Playground/BotTravelViews.swift", avatar: .smile),
            Item("旅行创建失败", "这次旅行暂时无法出发", .failure, .inline, "旅行校验错误文字", "Features/Playground/BotTravelStore.swift"),
            Item("旅行相册为空", "相册还空着", .information, .empty, "系统空状态", "Features/Playground/BotTravelViews.swift"),
            Item("删除旅行记录确认", "确定删除这段旅行记录？", .confirmation, .confirmation, "系统确认面板", "Features/Playground/BotTravelViews.swift")
        ]),
        Group(id: "debug", title: "用量、调试与外观实验", items: [
            Item("用量读取失败", "用量暂时无法读取", .failure, .inline, "页面错误文字", "Features/Quota/QuotaView.swift"),
            Item("后端健康检查中", "正在检查连接…", .progress, .inline, "状态行进度", "Features/Settings/DebugView.swift", avatar: .inspect),
            Item("后端健康 / 异常", "连接正常", .success, .inline, "状态行正常 / 异常", "Features/Settings/DebugView.swift"),
            Item("健康检查失败", "暂时无法连接", .failure, .inline, "状态行 + 技术错误文字", "Features/Settings/DebugView.swift", avatar: .error),
            Item("服务器地址校验", "请填写有效的服务器地址", .warning, .field, "服务器输入错误文字", "Features/Settings/DebugView.swift"),
            Item("服务器地址保存", "服务器地址已保存", .success, .banner, "保存并重新检查", "Features/Settings/DebugView.swift"),
            Item("外观草稿未保存", "当前外观尚未保存", .information, .inline, "实验室状态文字", "Features/Settings/RobotAvatarLabView.swift"),
            Item("本机外观保存 / 加载 / 清除", "本机外观已更新", .success, .banner, "实验室 message 文字", "Features/Settings/BotAvatarAppearanceSaveView.swift"),
            Item("清除外观确认", "确定清除这份外观配置？", .confirmation, .confirmation, "系统确认面板", "Features/Settings/BotAvatarAppearanceSaveView.swift"),
            Item("外观配置读取 / 保存失败", "外观配置暂时无法使用", .failure, .inline, "实验室 message 文字", "Features/Settings/RobotAvatarLabView.swift", detail: "原有配置已保留"),
            Item("形象未安装 / 回读未验证", "这份外观暂时无法应用", .warning, .inline, "外观保存页错误文字", "Features/Settings/BotAvatarAppearanceSaveView.swift"),
            Item("指定 Bot 外观更新", "Bot 外观已更新", .success, .banner, "保存页回读结果文字", "Features/Settings/BotAvatarAppearanceSaveView.swift")
        ])
    ]
}
