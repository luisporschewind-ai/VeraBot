"""attachments 表的 SQL（schema v12，表结构见 db/migrations/v012_attachments.py）。

所有查询都带 user_id（租户隔离），对账（reconcile）除外。文件读写、配额 / 过期规则留在
services/attachments/repo.py；这里只放 SQL，调用方传入同一条连接以保持事务。
"""
from __future__ import annotations

from .database import row, rows


def count_since(c, user_id: int, since: str) -> int:
    return c.execute("SELECT COUNT(*) FROM attachments WHERE user_id=? AND created_at>=?",
                     (user_id, since)).fetchone()[0]


def bytes_used(c, user_id: int) -> int:
    return c.execute("SELECT COALESCE(SUM(bytes),0) FROM attachments WHERE user_id=?", (user_id,)).fetchone()[0]


def insert_pending(c, *, att_id: str, user_id: int, bot_id: int | None, mime: str, nbytes: int, width: int,
                   height: int, sha256: str, storage_backend: str, storage_key: str, thumb_key: str | None,
                   created_at: str, expires_at: str) -> None:
    c.execute(
        "INSERT INTO attachments(id,user_id,bot_id,message_id,kind,mime,bytes,width,height,sha256,"
        "storage_backend,storage_key,thumb_key,status,created_at,expires_at)"
        " VALUES (?,?,?,NULL,'image',?,?,?,?,?,?,?,?,'pending',?,?)",
        (att_id, user_id, bot_id, mime, nbytes, width, height, sha256, storage_backend, storage_key, thumb_key,
         created_at, expires_at))


def get(c, user_id: int, att_id: str) -> dict | None:
    return row(c.execute("SELECT * FROM attachments WHERE id=? AND user_id=?", (att_id, user_id)).fetchone())


def for_messages(c, user_id: int, ids: list[int]):
    """→ sqlite3.Row 列表，按 created_at, id 排序。ids 非空。"""
    q = ",".join("?" * len(ids))
    return c.execute(f"SELECT * FROM attachments WHERE user_id=? AND message_id IN ({q}) ORDER BY created_at, id",
                     (user_id, *ids)).fetchall()


def attach(c, user_id: int, att_id: str, message_id: int, bot_id: int) -> None:
    """pending → attached（只改 pending 的行）。"""
    c.execute("UPDATE attachments SET status='attached', message_id=?, bot_id=?, expires_at=NULL"
              " WHERE id=? AND user_id=? AND status='pending'", (message_id, bot_id, att_id, user_id))


def set_caption(c, user_id: int, att_id: str, caption: str | None, status: str) -> None:
    c.execute("UPDATE attachments SET caption=?, caption_status=? WHERE id=? AND user_id=?",
              (caption, status, att_id, user_id))


def delete(c, user_id: int, att_id: str) -> None:
    c.execute("DELETE FROM attachments WHERE id=? AND user_id=?", (att_id, user_id))


def delete_for_bot(c, user_id: int, bot_id: int) -> None:
    c.execute("DELETE FROM attachments WHERE user_id=? AND bot_id=?", (user_id, bot_id))


def list_for_bot(c, user_id: int, bot_id: int) -> list[dict]:
    return rows(c.execute("SELECT * FROM attachments WHERE user_id=? AND bot_id=?", (user_id, bot_id)))


def list_for_message(c, user_id: int, bot_id: int, message_id: int) -> list[dict]:
    """删除单条消息前取该消息的图片行（Q12）；行本身随 messages 外键级联删除。"""
    return rows(c.execute("SELECT * FROM attachments WHERE user_id=? AND bot_id=? AND message_id=?",
                          (user_id, bot_id, message_id)))


def list_for_user(c, user_id: int) -> list[dict]:
    return rows(c.execute("SELECT * FROM attachments WHERE user_id=?", (user_id,)))


# ---------------------------------------------------------------- 对账（跨用户）
def expired_pending(c, now: str) -> list[dict]:
    return rows(c.execute("SELECT * FROM attachments WHERE status='pending' AND expires_at<?", (now,)))


def delete_by_id(c, att_id: str) -> None:
    c.execute("DELETE FROM attachments WHERE id=?", (att_id,))


def all_keys(c) -> list[dict]:
    return rows(c.execute("SELECT id, storage_key, thumb_key FROM attachments"))
