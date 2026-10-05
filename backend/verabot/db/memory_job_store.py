"""memory_jobs 表（记忆后台任务队列，schema v14，MEMORY_GROWTH §11.1）的 SQL。

业务规则（何时入队、执行什么）在 services/memory/jobs.py；这里只放 SQL，调用方传入同一条连接。
"""
from __future__ import annotations

from .database import now_iso, row, rows


def enqueue(c, user_id: int, bot_id: int | None, kind: str, after_message_id: int | None = None) -> bool:
    """入队。同一 (user, bot, kind) 已有 pending/running 时由部分唯一索引忽略，返回是否新建。"""
    cur = c.execute("INSERT OR IGNORE INTO memory_jobs(user_id, bot_id, kind, status, after_message_id, created_at) "
                    "VALUES (?,?,?,'pending',?,?)", (user_id, bot_id, kind, after_message_id, now_iso()))
    return cur.rowcount > 0


def claim_next(c) -> dict | None:
    """原子领取一条 pending（→ running，attempts+1）。并发 / 多 worker 下同一行只会被领到一次。"""
    r = c.execute("SELECT id FROM memory_jobs WHERE status='pending' ORDER BY id LIMIT 1").fetchone()
    if r is None:
        return None
    if c.execute("UPDATE memory_jobs SET status='running', attempts=attempts+1 WHERE id=? AND status='pending'",
                 (r["id"],)).rowcount == 0:
        return None
    return row(c.execute("SELECT * FROM memory_jobs WHERE id=?", (r["id"],)).fetchone())


def finish(c, job_id: int, status: str, error: str | None = None) -> None:
    """status: done / failed / skipped。error 只存短文案，不含正文。"""
    c.execute("UPDATE memory_jobs SET status=?, error=?, finished_at=? WHERE id=?",
              (status, (error or "")[:300] or None, now_iso(), job_id))


def recover_running(c) -> int:
    """启动时把上次进程遗留的 running 退回 pending（重启安全）；返回恢复条数。"""
    return c.execute("UPDATE memory_jobs SET status='pending' WHERE status='running'").rowcount


def pending_count(c, user_id: int | None = None) -> int:
    sql = "SELECT COUNT(*) FROM memory_jobs WHERE status IN ('pending','running')"
    params: tuple = ()
    if user_id is not None:
        sql += " AND user_id=?"
        params = (user_id,)
    return c.execute(sql, params).fetchone()[0]


def open_for(c, user_id: int, bot_id: int, kind: str) -> dict | None:
    return row(c.execute("SELECT * FROM memory_jobs WHERE user_id=? AND bot_id=? AND kind=? "
                         "AND status IN ('pending','running') ORDER BY id DESC LIMIT 1",
                         (user_id, bot_id, kind)).fetchone())


def recent(c, user_id: int, limit: int = 20) -> list[dict]:
    return rows(c.execute("SELECT * FROM memory_jobs WHERE user_id=? ORDER BY id DESC LIMIT ?",
                          (user_id, limit)).fetchall())


def delete_for_bot(c, user_id: int, bot_id: int) -> int:
    return c.execute("DELETE FROM memory_jobs WHERE user_id=? AND bot_id=?", (user_id, bot_id)).rowcount
