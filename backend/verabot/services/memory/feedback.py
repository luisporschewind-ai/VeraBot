"""消息反馈（👍 / 👎）。只评本人的 assistant 消息；👎 的 too_long 在 14 天内凑满次数后提议风格记忆。

提议只是 proposed，确认卡片由调用方把 style_trace 交给客户端。审计不写消息正文。
"""
from __future__ import annotations

import json
import logging

from ... import db
from ...core import config
from ...db import feedback_store, message_store
from ...services.memory import repository as repo
from . import style
from .errors import MemoryServiceError

log = logging.getLogger("verabot.memory.feedback")
REASONS = ("too_long", "too_short", "inaccurate", "tone", "other")


def _own_assistant(c, user_id: int, message_id: int) -> dict:
    msg = message_store.get_owned(c, user_id, message_id)
    if not msg or msg["role"] != "assistant":
        raise MemoryServiceError(404, "not_found", "消息不存在")
    return msg


def _public(row: dict | None) -> dict | None:
    if not row:
        return None
    return {"message_id": row["message_id"], "rating": row["rating"], "reason": row["reason"]}


def _maybe_style(user_id: int, bot: dict, message_id: int, reason: str | None) -> dict | None:
    content = style.REASON_STYLE.get(reason or "")
    if not content:
        return None
    with db.tx() as c:
        since = repo.iso_in(-config.MEMORY_STYLE_WINDOW_DAYS)
        n = feedback_store.count_reason(c, user_id, bot["id"], reason, since)
    if n < config.MEMORY_STYLE_MIN_FEEDBACK:
        return None
    from .service import propose_style
    proposal = propose_style(user_id, bot, content, user_message_id=message_id)
    if not proposal or proposal.get("status") != "proposed":
        return None
    return proposal


def _attach_trace(user_id: int, message_id: int, proposal: dict) -> dict:
    trace = style.trace_for(proposal)
    with db.tx() as c:
        msg = message_store.get_owned(c, user_id, message_id)
        if not msg:
            return trace
        try:
            traces = json.loads(msg["traces"]) if msg.get("traces") else []
        except json.JSONDecodeError:
            traces = []
        if not isinstance(traces, list):
            traces = []
        if any(isinstance(t, dict) and t.get("id") == trace["id"] for t in traces):
            return trace
        traces.append(trace)
        message_store.set_traces(c, user_id, message_id, json.dumps(traces, ensure_ascii=False))
    return trace


def submit(user_id: int, message_id: int, rating: int, reason: str | None) -> dict:
    if rating not in (1, -1):
        raise MemoryServiceError(422, "invalid_rating", "评分只能是 1 或 -1")
    if rating == -1 and reason not in REASONS:
        raise MemoryServiceError(422, "invalid_reason", "请选择不满意的原因")
    if rating == 1:
        reason = None
    with db.tx() as c:
        msg = _own_assistant(c, user_id, message_id)
        row = feedback_store.upsert(c, user_id=user_id, bot_id=msg["bot_id"], message_id=message_id,
                                    rating=rating, reason=reason)
        db.audit_in(c, user_id, msg["bot_id"], "message_feedback",
                    {"message_id": message_id, "rating": rating, "reason": reason})
    bot = db.get_bot(user_id, msg["bot_id"])
    proposal = _maybe_style(user_id, bot, message_id, reason) if bot else None
    style_trace = _attach_trace(user_id, message_id, proposal) if proposal else None
    log.info("feedback saved: user=%s message=%s rating=%s reason=%s proposed=%s",
             user_id, message_id, rating, reason, bool(style_trace))
    return {"ok": True, "feedback": _public(row), "style_trace": style_trace}


def clear(user_id: int, message_id: int) -> dict:
    with db.tx() as c:
        msg = _own_assistant(c, user_id, message_id)
        feedback_store.delete_for_message(c, user_id, message_id)
        db.audit_in(c, user_id, msg["bot_id"], "message_feedback_cleared", {"message_id": message_id})
    return {"ok": True}
