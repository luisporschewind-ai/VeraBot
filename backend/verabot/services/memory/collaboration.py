"""根据用户对委派回答的反馈，生成只读、受限的协作提示。"""
import json
import re

from ... import db
from .policy import render_safe


_TOPICS = (
    ("编程", re.compile(r"代码|编程|程序|软件|接口|bug|python|swift|ios|api", re.I)),
    ("写作", re.compile(r"写作|文案|文章|邮件|润色|改写|标题|翻译")),
    ("饮食", re.compile(r"吃|菜|食谱|餐|烹饪|做饭|食材|营养")),
    ("出行", re.compile(r"旅行|旅游|行程|酒店|机票|路线|景点|出差")),
)


def _topic(question: str) -> str:
    for name, pattern in _TOPICS:
        if pattern.search(question or ""):
            return name
    return "一般咨询"


def prompt_hints(user_id: int, bot: dict) -> list[str]:
    """仅从本用户对 depth-0 Bot 成功委派后的评分统计，返回最多三条方向提示。"""
    if not bot or not bot.get("id") or not (bot.get("allowed_tools") or []):
        return []
    from ...agents.permissions import delegation_targets
    eligible = {target["id"]: target for target in delegation_targets(user_id, bot)}
    if not eligible:
        return []
    with db.tx() as c:
        rows = c.execute(
            "SELECT m.traces, f.rating FROM messages m JOIN message_feedback f "
            "ON f.user_id=m.user_id AND f.message_id=m.id "
            "WHERE m.user_id=? AND m.bot_id=? AND m.role='assistant' AND m.traces IS NOT NULL "
            "ORDER BY f.created_at DESC LIMIT 500", (user_id, bot["id"])).fetchall()
        stats = {}
        feedback_count = 0
        for row in rows:
            try:
                traces = json.loads(row["traces"] or "[]")
            except (TypeError, json.JSONDecodeError):
                continue
            if not isinstance(traces, list):
                continue
            delegation_ids = []
            for trace in traces:
                result = trace.get("result") if isinstance(trace, dict) else None
                if isinstance(trace, dict) and trace.get("name") == "ask_bot" and isinstance(result, dict):
                    did = result.get("delegation_id")
                    if isinstance(did, int) and not isinstance(did, bool):
                        delegation_ids.append(did)
            if not delegation_ids:
                continue
            records = c.execute(
                f"SELECT id,to_bot_id,question FROM delegations WHERE user_id=? AND from_bot_id=? "
                f"AND status='ok' AND depth=1 AND id IN ({','.join('?' * len(delegation_ids))})",
                (user_id, bot["id"], *delegation_ids)).fetchall()
            records = [d for d in records if d["to_bot_id"] in eligible]
            # 一条助手回答只有一份评分；多目标委派时无法可靠归因，因此整条反馈不参与协作统计。
            if len(records) != 1:
                continue
            feedback_count += 1
            record = records[0]
            key = (_topic(record["question"]), record["to_bot_id"])
            stat = stats.setdefault(key, {"count": 0, "positive": 0})
            stat["count"] += 1
            stat["positive"] += int(row["rating"] == 1)

    if feedback_count < 3:
        return []
    candidates = [(topic, target_id, values) for (topic, target_id), values in stats.items() if values["count"] >= 2]
    candidates.sort(key=lambda item: (item[2]["positive"] / item[2]["count"], item[2]["count"], item[0]), reverse=True)
    return [f"在「{topic}」问题上，用户近期对咨询「{render_safe(eligible[target_id]['name'], 50)}」的委派回答反馈较好，可优先考虑它。"
            for topic, target_id, _ in candidates[:3]]
