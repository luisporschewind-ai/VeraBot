"""message_feedback 表的 SQL。只存评分与原因代码，不存消息正文。"""
from __future__ import annotations

from .database import now_iso, row


def upsert(c, *, user_id: int, bot_id: int, message_id: int, rating: int, reason: str | None) -> dict:
    """同一用户对同一条消息只有一行（可改评分）。改评时刷新 created_at，14 天窗口按最近一次评分计。"""
    now = now_iso()
    c.execute(
        "INSERT INTO message_feedback(user_id,bot_id,message_id,rating,reason,created_at) VALUES (?,?,?,?,?,?) "
        "ON CONFLICT(user_id, message_id) DO UPDATE SET bot_id=excluded.bot_id, rating=excluded.rating, "
        "reason=excluded.reason, created_at=excluded.created_at",
        (user_id, bot_id, message_id, rating, reason, now))
    return get_for_message(c, user_id, message_id)


def get_for_message(c, user_id: int, message_id: int) -> dict | None:
    return row(c.execute(
        "SELECT message_id, rating, reason, created_at FROM message_feedback WHERE user_id=? AND message_id=?",
        (user_id, message_id)).fetchone())


def delete_for_message(c, user_id: int, message_id: int) -> int:
    return c.execute("DELETE FROM message_feedback WHERE user_id=? AND message_id=?",
                     (user_id, message_id)).rowcount


def count_reason(c, user_id: int, bot_id: int, reason: str, since: str) -> int:
    return c.execute(
        "SELECT COUNT(*) FROM message_feedback WHERE user_id=? AND bot_id=? AND rating=-1 AND reason=? "
        "AND created_at>=?", (user_id, bot_id, reason, since)).fetchone()[0]
