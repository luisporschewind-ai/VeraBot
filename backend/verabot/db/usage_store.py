"""用量看板（Quota）与语音转写计数的 SQL：usage_log / transcriptions（delegations 计数见 delegation_store）。

usage_log 的写入与今日预算见 db/repository.py（log_usage / token_budget）。调用方传入同一条连接以保持事务。
"""
from __future__ import annotations

from .database import row, rows

_USAGE_Q = ("SELECT COUNT(*) AS requests, COALESCE(SUM(prompt_tokens),0) AS prompt_tokens, "
            "COALESCE(SUM(completion_tokens),0) AS completion_tokens, COALESCE(SUM(total_tokens),0) AS total_tokens "
            "FROM usage_log WHERE user_id=?")
_TRANSCRIBE_Q = ("SELECT COUNT(*) AS requests, COALESCE(SUM(duration_s),0) AS seconds, COALESCE(SUM(chars),0) AS chars "
                 "FROM transcriptions WHERE user_id=?")


def usage_totals(c, user_id: int, since: str | None = None) -> dict:
    """{requests, prompt_tokens, completion_tokens, total_tokens}；since 为 UTC ISO 时只算其后的。"""
    if since is None:
        return row(c.execute(_USAGE_Q, (user_id,)).fetchone())
    return row(c.execute(_USAGE_Q + " AND created_at>=?", (user_id, since)).fetchone())


def per_bot_usage(c, user_id: int) -> list[dict]:
    return rows(c.execute(
        "SELECT b.id, b.name, b.avatar, b.color, b.image_updated_at, COUNT(u.id) AS requests, "
        "COALESCE(SUM(u.total_tokens),0) AS total_tokens FROM bots b "
        "LEFT JOIN usage_log u ON u.bot_id=b.id AND u.user_id=b.user_id "
        "WHERE b.user_id=? GROUP BY b.id ORDER BY total_tokens DESC", (user_id,)).fetchall())


def usage_since(c, user_id: int, since: str):
    """逐条 (created_at, total_tokens)，给 7 日趋势按本地日期汇总。"""
    return c.execute("SELECT created_at, total_tokens FROM usage_log WHERE user_id=? AND created_at>=?",
                     (user_id, since)).fetchall()


def transcribe_totals(c, user_id: int, since: str | None = None) -> dict:
    """{requests, seconds, chars}；since 同上。"""
    if since is None:
        return row(c.execute(_TRANSCRIBE_Q, (user_id,)).fetchone())
    return row(c.execute(_TRANSCRIBE_Q + " AND created_at>=?", (user_id, since)).fetchone())


def insert_transcription(c, user_id: int, model: str, nbytes: int, duration_s, chars: int, total_tokens: int,
                         created_at: str) -> None:
    c.execute("INSERT INTO transcriptions(user_id,model,bytes,duration_s,chars,total_tokens,created_at)"
              " VALUES (?,?,?,?,?,?,?)",
              (user_id, model, nbytes, duration_s, chars, total_tokens, created_at))
