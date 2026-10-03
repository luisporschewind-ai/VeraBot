"""delegations 表的写入与查询。委派成功 / 被拒绝（agents/delegation.py）与工具层拒绝（agents/tool_router.py）共用同一条 INSERT。"""
from __future__ import annotations

from .database import now_iso, rows, tx


def insert(*, user_id: int, from_bot_id: int, to_bot_id: int, question: str, shared_context: str, answer: str,
           status: str, reason: str, depth: int, payload: str | None = None, shared_truncated: int = 0,
           prompt_tokens: int = 0, completion_tokens: int = 0, total_tokens: int = 0) -> int:
    """单独事务写入一条委派记录，返回新 id。未传的列取与表默认值相同的值（payload=NULL，计数列为 0）。"""
    with tx() as c:
        return c.execute(
            "INSERT INTO delegations(user_id,from_bot_id,to_bot_id,question,shared_context,answer,created_at,status,reason,"
            "depth,payload,shared_truncated,prompt_tokens,completion_tokens,total_tokens) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (user_id, from_bot_id, to_bot_id, question, shared_context, answer, now_iso(), status, reason,
             depth, payload, shared_truncated, prompt_tokens, completion_tokens, total_tokens)).lastrowid


def list_for_bot(c, user_id: int, bot_id: int, limit: int) -> list[dict]:
    """协作记录：该 Bot 发起或接收的委派（含双方名称 / 头像），新的在前。"""
    return rows(c.execute(
        "SELECT d.id, d.from_bot_id, fb.name AS from_bot, fb.avatar AS from_avatar, d.to_bot_id, tb.name AS to_bot, "
        "tb.avatar AS to_avatar, d.question, d.shared_context, d.shared_truncated, d.payload, d.answer, d.status, "
        "d.reason, d.depth, d.prompt_tokens, d.completion_tokens, d.total_tokens, d.created_at "
        "FROM delegations d LEFT JOIN bots fb ON fb.id=d.from_bot_id LEFT JOIN bots tb ON tb.id=d.to_bot_id "
        "WHERE d.user_id=? AND (d.from_bot_id=? OR d.to_bot_id=?) ORDER BY d.id DESC LIMIT ?",
        (user_id, bot_id, bot_id, limit)).fetchall())


def count_for_user(c, user_id: int) -> int:
    return c.execute("SELECT COUNT(*) FROM delegations WHERE user_id=?", (user_id,)).fetchone()[0]
