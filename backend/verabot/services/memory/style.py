"""风格校准（M2，MEMORY_GROWTH §11.1）：把「再短一点」这类要求与 👎 反馈变成 style 记忆提议。

两条来路，同一张确认卡片（type='style', scope='bot', source='feedback'，卡片标题「以后都这样回答吗？」）：
1. 规则命中：本轮用户消息里有明确的风格要求 → run_chat 在写库前追加一条合成 remember trace；
2. 聚合：14 天内同一 Bot 3 次 👎「太长」→ services/memory/feedback 记完评价后提议。

只提议、不自动生效：确认后才是 active，注入时排在本 Bot 记忆最前（recall.PINNED_TYPES）。
"""
from __future__ import annotations

import logging

from ... import db
from ...core import config
from ...db import feedback_store, memory_store
from . import policy
from . import repository as repo
from . import service

log = logging.getLogger("verabot.memory")

TOO_LONG_TEXT = "回答更简短，直接说重点"
TOO_SHORT_TEXT = "回答更详细一些，多给具体信息"
INACCURATE_TEXT = "回答问题前先核实事实，不确定就说明"

# 规则表：短语 → 提议的记忆正文（命中即提议；任一短语命中一次只提议一条）
PHRASES: tuple[tuple[tuple[str, ...], str], ...] = (
    (("再短一点", "短一点", "简短点", "简短一点", "简洁点", "简洁一点", "简洁些", "简单点", "说重点", "别啰嗦", "不要啰嗦", "太长了"),
     TOO_LONG_TEXT),
    (("详细一点", "详细点", "具体一点", "具体点", "展开说", "展开讲讲", "多说点"), TOO_SHORT_TEXT),
    (("别用列表", "不要用列表", "不用列表", "别列点", "不要列点", "别分点"), "回答不要用列表，用自然段落"),
    (("用列表", "分点说", "分条说", "列个清单", "列个表"), "回答用列表分点，方便扫读"),
    (("用英文", "说英文", "英文回答", "用英语"), "用英文回答"),
    (("用中文", "说中文", "中文回答"), "用中文回答"),
    (("别用表情", "不要表情", "别用emoji", "不要emoji", "别用 emoji", "不要 emoji"), "回答不要用 emoji"),
    (("正式一点", "正式点", "专业一点", "专业点"), "语气更正式、专业一些"),
    (("随意一点", "口语一点", "轻松一点", "别这么正式"), "语气更口语、轻松一些"),
)
REASON_TEXT = {"too_long": TOO_LONG_TEXT, "too_short": TOO_SHORT_TEXT, "inaccurate": INACCURATE_TEXT}


def detect(text: str) -> str | None:
    """用户消息命中的风格要求 → 提议正文；没有命中返回 None。"""
    t = policy.clean(text)
    if not t:
        return None
    for keys, content in PHRASES:
        if any(k in t for k in keys):
            return content
    return None


def _create_proposal(c, user_id: int, bot: dict, content: str, source_message_id: int | None) -> dict | None:
    """在事务内建 style 提议（去重 / 冷却与 service.propose 一致）。返回 None 表示不必提议。"""
    text = policy.clean(content)
    code, sensitivity = policy.check(text)
    if code:
        return None
    h = policy.content_hash(text, sensitivity)
    bot_id = bot["id"]
    if memory_store.find_by_hash(c, user_id, "bot", bot_id, h, service.LIVE):
        return None                                    # 已有生效 / 待确认的同款风格
    declined = memory_store.recently_declined(c, user_id, "bot", bot_id, h,
                                              repo.iso_in(-config.MEMORY_REJECT_COOLDOWN_DAYS))
    if declined:
        return None
    col, enc = repo.stored(text, sensitivity)
    mid = repo.insert(c, user_id=user_id, scope="bot", bot_id=bot_id, type="style", content=col, content_enc=enc,
                      content_hash=h, source="feedback", source_bot_id=bot_id, source_message_id=source_message_id,
                      status="proposed", action="create", sensitivity=sensitivity,
                      expires_at=repo.iso_in(config.MEMORY_PROPOSAL_TTL_DAYS))
    service._audit(c, user_id, bot_id, "memory_proposed", memory_id=mid, action="create", type="style",
                   scope="bot", bot_id=bot_id, source="feedback")
    log.info("style proposed: user=%s bot=%s id=%s", user_id, bot_id, mid)
    return service._proposal_result(c, user_id, mid)


def propose_from_text(user_id: int, bot: dict, turn, text: str, user_message_id: int | None = None) -> dict | None:
    """规则命中：返回合成 remember trace 用的提议结果（None = 不提议）。由 run_chat 调用。"""
    if not service.enabled_for(user_id) or (bot.get("memory_access") or "none") == "none":
        return None
    content = detect(text)
    if not content:
        return None
    if turn.memory_proposals >= config.MEMORY_PROPOSALS_PER_TURN:
        return None
    with db.tx() as c:
        out = _create_proposal(c, user_id, bot, content, user_message_id)
    if out:
        turn.memory_proposals += 1
    return out


def propose_from_feedback(user_id: int, bot_id: int, message_id: int) -> dict | None:
    """👎「太长 / 太短 / 不准确」聚合：窗口内同一 Bot 同理由 ≥ N 次 → 提议（同一 Bot 只提议一条）。"""
    if not service.enabled_for(user_id):
        return None
    bot = db.get_bot(user_id, bot_id)
    if not bot or (bot.get("memory_access") or "none") == "none":
        return None
    with db.tx() as c:
        for reason, content in REASON_TEXT.items():
            since = repo.iso_in(-config.MEMORY_STYLE_TOO_LONG_WINDOW_DAYS)
            n = feedback_store.count_recent(c, user_id, bot_id, reason, since)
            if n < config.MEMORY_STYLE_TOO_LONG_MIN:
                continue
            return _create_proposal(c, user_id, bot, content, message_id)
    return None


def synthetic_trace(trace_id: str, proposal: dict) -> dict:
    """把提议包装成一条 remember 工具的合成 trace：客户端按既有卡片逻辑渲染（无需新协议）。"""
    return {"id": trace_id, "name": "remember",
            "args": {"content": proposal.get("content"), "type": "style", "scope": "bot"},
            "result": proposal}
