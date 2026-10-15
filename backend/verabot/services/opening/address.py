"""从生效记忆里轻量解析称呼偏好；不碰敏感内容。"""
from __future__ import annotations

import re

from ... import db
from ...db import memory_store

# 只接受短称呼；拒绝像地址/电话一类的长串
_MAX_LEN = 16
_PATTERNS = (
    re.compile(r"(?:称呼(?:用户)?为|叫我|请叫我|喊我|我叫)\s*[「『\"']?([^」』\"'\s，。；;、]{1,16})"),
    re.compile(r"希望被称呼为\s*[「『\"']?([^」』\"'\s，。；;、]{1,16})"),
)
_BLOCK = re.compile(r"(密码|住址|地址|电话|手机|身份证|银行卡|病|医院|工资|账号)", re.I)


def preferred_address(user_id: int, bot_id: int | None = None) -> str | None:
    """返回可用称呼，或 None。优先本 Bot profile，其次全局 profile。"""
    with db.tx() as c:
        rows = memory_store.list_filtered(
            c, user_id, statuses=("active",), scope=None, bot_id=None,
            ids=None, before_id=None, visible_to=None, limit=80,
        )
    candidates: list[tuple[int, str]] = []
    for r in rows:
        if (r.get("type") or "") != "profile":
            continue
        if (r.get("status") or "") != "active":
            continue
        scope = r.get("scope") or ""
        if scope == "bot" and bot_id is not None and r.get("bot_id") != bot_id:
            continue
        if scope not in ("bot", "global"):
            continue
        content = (r.get("content") or "").strip()
        if not content or _BLOCK.search(content):
            continue
        parsed = _parse(content)
        if not parsed:
            continue
        # 本 Bot 记忆优先于全局
        rank = 0 if scope == "bot" and r.get("bot_id") == bot_id else 1
        candidates.append((rank, parsed))
    if not candidates:
        return None
    candidates.sort(key=lambda x: x[0])
    return candidates[0][1]


def _parse(content: str) -> str | None:
    for pat in _PATTERNS:
        m = pat.search(content)
        if not m:
            continue
        name = m.group(1).strip("「」『』\"' ")
        if not name or len(name) > _MAX_LEN or _BLOCK.search(name):
            continue
        if any(ch.isdigit() for ch in name) and len(name) > 4:
            continue
        return name
    return None
