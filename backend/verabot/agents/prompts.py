"""System Prompt 组装（Prompts）：只列出有权限的能力与委派目标；被委派时使用独立的简短 prompt。"""
from datetime import datetime
from zoneinfo import ZoneInfo

from ..core.config import TIMEZONE
from .context import public_profile
from .permissions import delegation_targets, is_permitted


def system_prompt(user_id: int, bot: dict, delegated_by: dict | None = None, depth: int = 0) -> str:
    now = datetime.now(ZoneInfo(TIMEZONE)).strftime("%Y-%m-%d %H:%M (%A)")
    parts = [
        f"你是「{bot['name']}」，是用户的私人 AI 助理（VeraBot 平台上的一个 Bot）。",
        f"当前时间：{now}，时区 {TIMEZONE}。",
    ]
    if bot.get("persona"):
        parts.append(f"【人设 Persona】{bot['persona']}")
    if bot.get("instructions"):
        parts.append(f"【自定义指令 Instructions】{bot['instructions']}")
    can = lambda name: is_permitted(bot, name, depth)[0]
    if delegated_by is None:
        targets = delegation_targets(user_id, bot) if can("ask_bot") else []
        if targets:
            lst = "；".join(public_profile(b) for b in targets)
            parts.append(f"你可以咨询这些 Bot 同事：{lst}。当问题更适合对方的专长，或用户明确要求时，"
                         "使用 ask_bot 工具咨询对方，并把必要背景放入 shared_context（对方看不到本对话）。"
                         "当用户要求你去问/咨询/请教某个 Bot 时，必须每次都真实调用 ask_bot，"
                         "即使历史中问过相同问题，也要重新调用；严禁凭记忆或自行编造对方的回答。"
                         "如果用户要求咨询不在上述名单中的 Bot，照常调用 ask_bot，由系统判定是否有权限。")
        rules = []
        if can("get_weather"):
            rules.append("需要实时天气时必须调用 get_weather（不要凭历史猜测）")
        if can("create_reminder") or can("list_reminders"):
            rules.append("用户要求提醒/待办时调用 create_reminder 或 list_reminders")
        rules.append("如果用户请求的能力你没有被授权，礼貌说明「这个 Bot 暂未开通该能力，可在 Bot 设置中开启」，不要编造结果")
        parts.append("；".join(rules) + "。回答使用用户的语言，简洁清晰。")
    else:
        parts.append(f"你正在被同一用户的另一个 Bot {public_profile(delegated_by)} 咨询。你看不到用户与它的对话，"
                     "只能依据对方提供的问题与共享背景作答。请直接给出专业、简洁的答复。"
                     "如果对方要求你再去转问其他 Bot，直接说明你无法转交、请对方自行咨询，并尽量就问题本身作答；"
                     "不要提及、列举或解释你的内部工具、函数名或系统配置。")
    return "\n".join(parts)
