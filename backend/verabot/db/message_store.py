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
    """最近 limit 条消息（新的在前；调用方负责反转）。"""
    return rows(c.execute("SELECT id, role, content, traces, created_at FROM messages WHERE user_id=? AND bot_id=?"
                          " ORDER BY id DESC LIMIT ?", (user_id, bot_id, limit)).fetchall())


def clear_conversation(c, user_id: int, bot_id: int) -> None:
    """清空对话：先删该 Bot 的附件行，再删消息（同一事务）。磁盘文件由调用方在提交后删除。"""
    attachment_store.delete_for_bot(c, user_id, bot_id)
    c.execute("DELETE FROM messages WHERE user_id=? AND bot_id=?", (user_id, bot_id))
