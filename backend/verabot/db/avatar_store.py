"""avatars 表的 SQL。用户头像 bot_id=0；Bot 头像 bot_id 为该 Bot 的 id。

只按 user_id 读写，调用方必须先确认归属；调用方传入同一条连接以保持事务（头像行 + 时间戳一起提交）。
"""
from __future__ import annotations


def upsert(c, user_id: int, bot_id: int, jpeg: bytes, now: str) -> None:
    c.execute(
        """INSERT INTO avatars(user_id, bot_id, content_type, data, updated_at)
           VALUES (?,?,?,?,?)
           ON CONFLICT(user_id, bot_id) DO UPDATE SET
             content_type=excluded.content_type,
             data=excluded.data,
             updated_at=excluded.updated_at""",
        (user_id, bot_id, "image/jpeg", jpeg, now),
    )


def delete_user(c, user_id: int) -> None:
    c.execute("DELETE FROM avatars WHERE user_id=? AND bot_id=0", (user_id,))


def delete_bot(c, user_id: int, bot_id: int) -> None:
    c.execute("DELETE FROM avatars WHERE user_id=? AND bot_id=?", (user_id, bot_id))


def read_user(c, user_id: int):
    """→ sqlite3.Row(data) 或 None。"""
    return c.execute("SELECT data FROM avatars WHERE user_id=? AND bot_id=0", (user_id,)).fetchone()


def read_bot(c, user_id: int, bot_id: int):
    """→ sqlite3.Row(data) 或 None。"""
    return c.execute(
        "SELECT data FROM avatars WHERE user_id=? AND bot_id=?", (user_id, bot_id)
    ).fetchone()
