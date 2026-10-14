"""messages 表的列表 / 清空查询（写入与对话上下文见 db/repository.py 的 add_message / recent_messages）。

调用方传入同一条连接以保持事务。
"""
from __future__ import annotations

from . import attachment_store
from .database import row, rows, tx
import json


def last_message(c, user_id: int, bot_id: int) -> dict | None:
    """Bot 列表的最后一条消息预览。"""
    return row(c.execute("SELECT content, created_at FROM messages WHERE user_id=? AND bot_id=? "
                         "ORDER BY id DESC LIMIT 1", (user_id, bot_id)).fetchone())


def list_recent(c, user_id: int, bot_id: int, limit: int) -> list[dict]:
    """最近 limit 条消息（新的在前；调用方负责反转）。附带本人对 assistant 消息的反馈（没有则为 NULL）。"""
    return rows(c.execute(
        "SELECT m.id, m.role, m.content, m.traces, m.created_at, m.message_status, m.source_kind, m.source_id, f.rating AS feedback_rating, f.reason AS feedback_reason "
        "FROM messages m LEFT JOIN message_feedback f ON f.message_id=m.id AND f.user_id=m.user_id "
        "WHERE m.user_id=? AND m.bot_id=? AND m.message_status NOT IN ('queued','running') ORDER BY m.id DESC LIMIT ?",
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


def user_message_stamp(c, message_id: int, user_id: int, bot_id: int):
    return c.execute(
        "SELECT id,created_at FROM messages WHERE id=? AND user_id=? AND bot_id=? AND role='user'",
        (message_id, user_id, bot_id)).fetchone()


def user_message_role(c, message_id: int, user_id: int, bot_id: int):
    return c.execute(
        "SELECT id,role,created_at FROM messages WHERE id=? AND user_id=? AND bot_id=? AND role='user'",
        (message_id, user_id, bot_id)).fetchone()


def count_user_messages_through(c, user_id: int, bot_id: int, after_id: int, through_id: int) -> int:
    return c.execute(
        "SELECT COUNT(*) FROM messages WHERE user_id=? AND bot_id=? AND role='user' AND id>? AND id<=?",
        (user_id, bot_id, after_id, through_id)).fetchone()[0]


def previous_message(c, user_id: int, bot_id: int, before_id: int):
    return c.execute(
        "SELECT role,created_at FROM messages WHERE user_id=? AND bot_id=? AND id<? ORDER BY id DESC LIMIT 1",
        (user_id, bot_id, before_id)).fetchone()


def recent_user_contents(c, user_id: int, bot_id: int, cutoff: str):
    return c.execute(
        "SELECT role,content FROM messages WHERE user_id=? AND bot_id=? AND role='user' AND created_at>=? ORDER BY id DESC LIMIT 1000",
        (user_id, bot_id, cutoff)).fetchall()


def user_message_created_at(c, message_id: int, user_id: int, bot_id: int):
    return c.execute(
        "SELECT created_at FROM messages WHERE id=? AND user_id=? AND bot_id=? AND role='user'",
        (message_id, user_id, bot_id)).fetchone()


def min_created_for_bots(c, user_id: int, bot_ids: list[int]):
    marks = ",".join("?" * len(bot_ids))
    return c.execute(
        f"SELECT MIN(created_at) FROM messages WHERE user_id=? AND bot_id IN ({marks})",
        (user_id, *bot_ids)).fetchone()[0]


def count_assistant_between(c, user_id: int, bot_ids: list[int], start: str, end: str) -> int:
    marks = ",".join("?" * len(bot_ids))
    return c.execute(
        f"SELECT COUNT(*) FROM messages WHERE user_id=? AND bot_id IN ({marks}) AND role='assistant' AND created_at>=? AND created_at<?",
        (user_id, *bot_ids, start, end)).fetchone()[0]


def count_assistant(c, user_id: int, bot_id: int) -> int:
    return c.execute(
        "SELECT COUNT(*) FROM messages WHERE user_id=? AND bot_id=? AND role='assistant'",
        (user_id, bot_id)).fetchone()[0]


def min_created_for_bot(c, user_id: int, bot_id: int):
    return c.execute(
        "SELECT MIN(created_at) FROM messages WHERE user_id=? AND bot_id=?",
        (user_id, bot_id)).fetchone()[0]


def memory_ids_json(c, message_id: int, user_id: int):
    return c.execute(
        "SELECT memory_ids FROM messages WHERE id=? AND user_id=?",
        (message_id, user_id)).fetchone()


def rated_assistant_traces(c, user_id: int, bot_id: int):
    return c.execute(
        "SELECT m.traces, f.rating FROM messages m JOIN message_feedback f "
        "ON f.user_id=m.user_id AND f.message_id=m.id "
        "WHERE m.user_id=? AND m.bot_id=? AND m.role='assistant' AND m.traces IS NOT NULL "
        "ORDER BY f.created_at DESC LIMIT 500", (user_id, bot_id)).fetchall()


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
    from . import conversation_activity_store
    conversation_activity_store.clear(c,user_id,"private",bot_id)
    attachment_store.delete_for_bot(c, user_id, bot_id)
    c.execute("DELETE FROM messages WHERE user_id=? AND bot_id=?", (user_id, bot_id))


def add_scheduled(c, user_id: int, bot_id: int, run_id: int, content: str, created_at: str) -> int:
    from .conversation_activity_store import generation
    return c.execute(
        "INSERT INTO messages(user_id,bot_id,role,content,created_at,source_kind,source_id,conversation_generation) "
        "VALUES(?,?,'assistant',?,?,'scheduled_task',?,?)",
        (user_id,bot_id,content,created_at,run_id,generation(c,user_id,"private",bot_id))).lastrowid


class ConversationSyncConflict(Exception):
    """A revision-pinned page no longer matches the requested snapshot."""


def sync_messages(user_id: int, bot_id: int, limit: int = 100,
                  before_id: int | None = None, expected_revision: int | None = None) -> dict:
    from ..services.attachments import repo as attachments
    with tx() as c:
        c.execute("BEGIN")
        from .conversation_activity_store import generation
        gen=generation(c,user_id,"private",bot_id)
        row = c.execute("SELECT revision FROM conversation_revisions WHERE user_id=? AND kind='private' AND conversation_id=?",
                        (user_id, bot_id)).fetchone()
        revision = int(row[0]) if row else 0
        if expected_revision is not None and expected_revision != revision:
            raise ConversationSyncConflict()
        if before_id is None and expected_revision == revision:
            return {"generation":gen, "revision": revision, "messages": [], "next_before_id": None, "unchanged": True}
        cursor = before_id if before_id is not None else 9223372036854775807
        found = c.execute("""SELECT m.id,m.role,m.content,m.traces,m.created_at,m.message_status,m.conversation_generation,
                              f.rating AS feedback_rating,f.reason AS feedback_reason
                           FROM messages m LEFT JOIN message_feedback f
                             ON f.message_id=m.id AND f.user_id=m.user_id
                           WHERE m.user_id=? AND m.bot_id=? AND m.id<?
                           ORDER BY m.id DESC LIMIT ?""", (user_id, bot_id, cursor, limit + 1)).fetchall()
        more = len(found) > limit
        page = list(reversed(found[:limit]))
        ids = [int(item["id"]) for item in page]
        att_map = {}
        if ids:
            marks = ",".join("?" for _ in ids)
            for attachment in c.execute(f"SELECT * FROM attachments WHERE user_id=? AND message_id IN ({marks}) ORDER BY created_at,id",
                                         (user_id, *ids)):
                att_map.setdefault(int(attachment["message_id"]), []).append(attachments.public(dict(attachment)))
        messages = []
        for item in page:
            rating, reason = item["feedback_rating"], item["feedback_reason"]
            messages.append({"id": item["id"], "role": item["role"], "content": item["content"],
                             "traces": json.loads(item["traces"]) if item["traces"] else [],
                             "message_status":item["message_status"], "generation":item["conversation_generation"],
                             "publication_revision":(c.execute("SELECT publication_revision FROM message_publications WHERE user_id=? AND kind='private' AND conversation_id=? AND generation=? AND message_id=?",(user_id,bot_id,item["conversation_generation"],item["id"])).fetchone() or [0])[0],
                             "created_at": item["created_at"], "attachments": att_map.get(int(item["id"]), []),
                             "feedback": {"rating": rating, "reason": reason}
                             if item["role"] == "assistant" and rating is not None else None})
        next_before_id = int(page[0]["id"]) if more and page else None
        from .conversation_activity_store import generation
        return {"generation":generation(c,user_id,"private",bot_id), "revision": revision, "messages": messages, "next_before_id": next_before_id, "unchanged": False}
