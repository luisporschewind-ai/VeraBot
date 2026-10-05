"""memory_jobs 表的 SQL。摘要 / 抽取任务入队与领取。调用方传入同一条连接以保持事务。

不读写记忆正文。error 只存短代码（below_threshold / budget / llm_error 等）。
"""
from __future__ import annotations

from .database import now_iso, row, rows


def enqueue(c, *, user_id: int, bot_id: int, kind: str, after_message_id: int | None) -> int:
    """同一用户、同一 Bot、同一 kind 最多一条 pending。已有 pending 时只把 after_message_id 向前拨。
    正在跑的任务不打断；若没有 pending，再插一条，等当前任务结束后处理。"""
    pending = row(c.execute(
        "SELECT id, after_message_id FROM memory_jobs WHERE user_id=? AND bot_id=? AND kind=? AND status='pending' "
        "ORDER BY id LIMIT 1", (user_id, bot_id, kind)).fetchone())
    if pending:
        old = pending["after_message_id"] or 0
        if after_message_id and after_message_id > old:
            c.execute("UPDATE memory_jobs SET after_message_id=? WHERE id=? AND user_id=?",
                      (after_message_id, pending["id"], user_id))
        return pending["id"]
    cur = c.execute(
        "INSERT INTO memory_jobs(user_id,bot_id,kind,status,after_message_id,attempts,created_at) "
        "VALUES (?,?,?,'pending',?,0,?)",
        (user_id, bot_id, kind, after_message_id, now_iso()))
    return cur.lastrowid


def recover_running(c) -> int:
    """进程重启：上次没跑完的 running 退回 pending，避免卡死。"""
    return c.execute("UPDATE memory_jobs SET status='pending' WHERE status='running'").rowcount


def claim_next(c) -> dict | None:
    """原子领取最早的 pending。单进程 worker 用；多进程部署见设计稿（M5）。"""
    pending = row(c.execute(
        "SELECT id FROM memory_jobs WHERE status='pending' ORDER BY id LIMIT 1").fetchone())
    if not pending:
        return None
    cur = c.execute(
        "UPDATE memory_jobs SET status='running', attempts=attempts+1 WHERE id=? AND status='pending'",
        (pending["id"],))
    if cur.rowcount != 1:
        return None
    return row(c.execute("SELECT * FROM memory_jobs WHERE id=?", (pending["id"],)).fetchone())


def finish(c, job_id: int, status: str, error: str | None) -> None:
    c.execute("UPDATE memory_jobs SET status=?, error=?, finished_at=? WHERE id=?",
              (status, (error or None), now_iso(), job_id))


def requeue(c, job_id: int, error: str) -> None:
    """失败但还可以重试：退回 pending，保留已增加的 attempts。"""
    c.execute("UPDATE memory_jobs SET status='pending', error=?, finished_at=NULL WHERE id=? AND status='running'",
              ((error or "")[:80], job_id))


def skip_pending(c, user_id: int, bot_id: int, kind: str, error: str) -> int:
    return c.execute(
        "UPDATE memory_jobs SET status='skipped', error=?, finished_at=? "
        "WHERE user_id=? AND bot_id=? AND kind=? AND status='pending'",
        (error, now_iso(), user_id, bot_id, kind)).rowcount


def get(c, job_id: int) -> dict | None:
    return row(c.execute("SELECT * FROM memory_jobs WHERE id=?", (job_id,)).fetchone())


def list_for(c, user_id: int, bot_id: int, kind: str) -> list[dict]:
    return rows(c.execute(
        "SELECT * FROM memory_jobs WHERE user_id=? AND bot_id=? AND kind=? ORDER BY id",
        (user_id, bot_id, kind)).fetchall())
