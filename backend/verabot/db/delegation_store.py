"""delegations 表的写入。委派成功 / 被拒绝（agents/delegation.py）与工具层拒绝（agents/tool_router.py）共用同一条 INSERT。"""
from __future__ import annotations

from .database import now_iso, tx


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
