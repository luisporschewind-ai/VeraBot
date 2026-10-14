"""audit_log 的读取。写入见 repository.audit。调用方传入同一条连接以保持事务。"""
from __future__ import annotations


def list_kinds(c, user_id: int, bot_id: int, kinds: tuple[str, ...], limit: int):
    placeholders = ",".join("?" * len(kinds))
    return c.execute(
        f"""SELECT id, kind, detail, created_at FROM audit_log
            WHERE user_id=? AND bot_id=? AND kind IN ({placeholders})
            ORDER BY id DESC LIMIT ?""",
        (user_id, bot_id, *kinds, limit),
    ).fetchall()
