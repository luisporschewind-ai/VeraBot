"""messages 表的列表 / 清空查询（写入与对话上下文见 db/repository.py 的 add_message / recent_messages）。

调用方传入同一条连接以保持事务。
"""
from __future__ import annotations

from . import attachment_store
from .database import row, rows


def last_message(c, user_id: int, bot_id: int) -> dict | None:
    """Bot 列表的最后一条消息预览。"""
    return row(c.execute("SELECT content, created_at FROM messages WHERE user_id=? AND bot_id=? "
                         "ORDER BY id DESC LIMIT 1", (user_id, bot_id)).fetchone())


def list_recent(c, user_id: int, bot_id: int, limit: int) -> list[dict]:
    """最近 limit 条消息（新的在前；调用方负责反转）。附带本人对 assistant 消息的反馈（没有则为 NULL）。"""
    return rows(c.execute(
        "SELECT m.id, m.role, m.content, m.traces, m.created_at, f.rating AS feedback_rating, f.reason AS feedback_reason "
        "FROM messages m LEFT JOIN message_feedback f ON f.message_id=m.id AND f.user_id=m.user_id "
        "WHERE m.user_id=? AND m.bot_id=? ORDER BY m.id DESC LIMIT ?",
        (user_id, bot_id, limit)).fetchall())


def get_owned(c, user_id: int, message_id: int) -> dict | None:
    """按 user_id + id 取一条消息（不存在或他人的都是 None）。"""
    return row(c.execute(
        "SELECT id, user_id, bot_id, role, traces FROM messages WHERE id=? AND user_id=?",
        (message_id, user_id)).fetchone())


def message_exists(c, user_id: int, bot_id: int, message_id: int) -> bool:
    return c.execute("SELECT 1 FROM messages WHERE id=? AND user_id=? AND bot_id=?",
                     (message_id, user_id, bot_id)).fetchone() is not None


def set_traces(c, user_id: int, message_id: int, traces_json: str) -> None:
    c.execute("UPDATE messages SET traces=? WHERE id=? AND user_id=?", (traces_json, message_id, user_id))


def list_conversation(c, user_id: int, bot_id: int) -> list[dict]:
    """该 Bot 的全部消息，旧的在前。摘要任务用来划分窗口，不写日志。"""
    return rows(c.execute(
        "SELECT id, role, content FROM messages WHERE user_id=? AND bot_id=? ORDER BY id",
        (user_id, bot_id)).fetchall())


def list_for_extraction(c, user_id: int, bot_id: int, after_message_id: int, limit: int = 64) -> list[dict]:
    """Recent conversation rows for implicit extraction; caller filters to user evidence and safe context."""
    found = rows(c.execute(
        "SELECT id, role, content, traces, created_at FROM messages "
        "WHERE user_id=? AND bot_id=? AND id<=? ORDER BY id DESC LIMIT ?",
        (user_id, bot_id, after_message_id, limit),
    ).fetchall())
    return list(reversed(found))


def clear_conversation(c, user_id: int, bot_id: int) -> None:
    """清空对话：先删该 Bot 的附件行，再删消息（同一事务）。磁盘文件由调用方在提交后删除。"""
    attachment_store.delete_for_bot(c, user_id, bot_id)
    c.execute("DELETE FROM messages WHERE user_id=? AND bot_id=?", (user_id, bot_id))
