"""message_feedback 表（消息级 👍 / 👎，schema v14，MEMORY_GROWTH §11.1）的 SQL。

同一 (user, message) 一行，改评走 upsert（rating / reason 覆盖，created_at 保留首次时间）。
业务规则（谁能评、评完怎么触发风格提议）在 services/memory/style.py。
"""
from __future__ import annotations

from .database import now_iso, row


def upsert(c, user_id: int, bot_id: int | None, message_id: int, rating: int, reason: str | None) -> None:
    now = now_iso()
    c.execute("INSERT INTO message_feedback(user_id, bot_id, message_id, rating, reason, created_at, updated_at) "
              "VALUES (?,?,?,?,?,?,?) "
              "ON CONFLICT(user_id, message_id) DO UPDATE SET rating=excluded.rating, reason=excluded.reason, "
              "bot_id=excluded.bot_id, updated_at=excluded.updated_at",
              (user_id, bot_id, message_id, rating, reason, now, now))


def delete(c, user_id: int, message_id: int) -> int:
    return c.execute("DELETE FROM message_feedback WHERE user_id=? AND message_id=?", (user_id, message_id)).rowcount


def get(c, user_id: int, message_id: int) -> dict | None:
    return row(c.execute("SELECT * FROM message_feedback WHERE user_id=? AND message_id=?",
                         (user_id, message_id)).fetchone())


def for_messages(c, user_id: int, message_ids: list[int]) -> dict[int, dict]:
    """{message_id: {rating, reason}}，供消息列表回显选中态。"""
    if not message_ids:
        return {}
    qs = ",".join("?" * len(message_ids))
    return {r["message_id"]: {"rating": r["rating"], "reason": r["reason"]} for r in
            c.execute(f"SELECT message_id, rating, reason FROM message_feedback "
                      f"WHERE user_id=? AND message_id IN ({qs})", (user_id, *message_ids)).fetchall()}


def count_recent(c, user_id: int, bot_id: int, reason: str, since: str) -> int:
    """窗口内该 Bot 的「同一理由」次数（风格聚合用：14 天内 3 次 too_long）。"""
    return c.execute("SELECT COUNT(*) FROM message_feedback WHERE user_id=? AND bot_id=? AND reason=? "
                     "AND created_at>=?", (user_id, bot_id, reason, since)).fetchone()[0]


def delete_for_bot(c, user_id: int, bot_id: int) -> int:
    """清空对话时一并删除该 Bot 的评价（消息已删，外键也会级联；显式删除便于统计）。"""
    return c.execute("DELETE FROM message_feedback WHERE user_id=? AND bot_id=?", (user_id, bot_id)).rowcount
