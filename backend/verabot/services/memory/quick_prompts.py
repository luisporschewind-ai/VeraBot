"""Safe, history-derived quick prompts for a Bot's chat composer."""
from __future__ import annotations

import re
from collections import Counter
from datetime import datetime, timedelta, timezone

from ... import db
from ...db import message_store
from . import policy

_END_PUNCT = "。.!！?？,，;；:："


def normalize(text: str) -> str:
    value = policy.clean(text)
    value = re.sub(r"\s+", " ", value).strip().rstrip(_END_PUNCT).strip()
    return value


def build(messages: list[dict], *, allowed_tools: list[str], limit: int = 6) -> list[str]:
    counts: Counter[str] = Counter()
    display: dict[str, str] = {}
    for message in messages:
        if message.get("role", "user") != "user":
            continue
        text = normalize(str(message.get("content") or ""))
        if not text or len(text) > 80:
            continue
        code, sensitivity = policy.check(text, max_chars=80)
        if code or sensitivity != "normal":
            continue
        key = re.sub(r"\s+", "", text).lower()
        counts[key] += int(message.get("count", 1) or 1)
        display.setdefault(key, text)
    prompts = [display[key] for key, n in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0])) if n >= 3][:4]
    seen = {re.sub(r"\s+", "", p).lower() for p in prompts}
    templates = []
    if "get_weather" in allowed_tools:
        templates.append("今天天气怎么样？")
    if "create_reminder" in allowed_tools or "manage_reminder" in allowed_tools:
        templates.append("帮我设置一个提醒")
    for prompt in templates:
        key = re.sub(r"\s+", "", normalize(prompt)).lower()
        if key not in seen:
            prompts.append(prompt)
            seen.add(key)
    return prompts[:max(0, min(int(limit), 6))]


def for_bot(user_id: int, bot_id: int) -> list[str]:
    bot = db.get_bot(user_id, bot_id)
    if not bot:
        return []
    cutoff = (datetime.now(timezone.utc) - timedelta(days=30)).isoformat()
    with db.tx() as c:
        messages = c.execute(
            "SELECT role,content FROM messages WHERE user_id=? AND bot_id=? AND role='user' AND created_at>=? ORDER BY id DESC LIMIT 1000",
            (user_id, bot_id, cutoff),
        ).fetchall()
    return build([dict(m) for m in messages], allowed_tools=bot.get("allowed_tools") or [], limit=6)
