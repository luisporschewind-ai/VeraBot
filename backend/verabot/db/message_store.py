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


def own_assistant(c, user_id: int, message_id: int) -> dict | None:
    """本人的 assistant 消息（消息反馈用）；他人的 / 不存在的 / 用户自己的消息统一返回 None。"""
    r = c.execute("SELECT id, bot_id, role FROM messages WHERE id=? AND user_id=?",
                  (message_id, user_id)).fetchone()
    return row(r) if r is not None and r["role"] == "assistant" else None


def window_start_id(c, user_id: int, bot_id: int, window: int) -> int | None:
    """最近 window 条里最旧那条的 id（摘要窗口边界：更早的消息才算「窗口外」）。不足 window 条返回 None。"""
    r = c.execute("SELECT id FROM messages WHERE user_id=? AND bot_id=? ORDER BY id DESC LIMIT 1 OFFSET ?",
                  (user_id, bot_id, max(window, 1) - 1)).fetchone()
    return r[0] if r else None


def range_between(c, user_id: int, bot_id: int, after_id: int, before_id: int, limit: int) -> list[dict]:
    """(after_id, before_id) 开区间内、有正文的消息，按 id 升序（摘要输入）。"""
    return rows(c.execute("SELECT id, role, content FROM messages WHERE user_id=? AND bot_id=? AND id>? AND id<? "
                          "AND content<>'' ORDER BY id LIMIT ?",
                          (user_id, bot_id, after_id, before_id, limit)).fetchall())


def max_id(c, user_id: int, bot_id: int) -> int | None:
    r = c.execute("SELECT MAX(id) FROM messages WHERE user_id=? AND bot_id=?", (user_id, bot_id)).fetchone()
    return r[0] if r and r[0] is not None else None


def clear_conversation(c, user_id: int, bot_id: int) -> None:
    """清空对话：先删该 Bot 的附件行，再删消息（同一事务）。磁盘文件由调用方在提交后删除。"""
    attachment_store.delete_for_bot(c, user_id, bot_id)
    c.execute("DELETE FROM messages WHERE user_id=? AND bot_id=?", (user_id, bot_id))
