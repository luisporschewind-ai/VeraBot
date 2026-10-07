"""pending_actions 表的查询（MCP M3 / 后续 Gmail / 提醒 R2 共用）。所有读写都带 user_id。"""
from __future__ import annotations

from .database import now_iso, tx


def _row(r):
    return None if r is None else dict(r)


def insert(
    user_id: int,
    *,
    bot_id: int | None,
    kind: str,
    server_id: int | None,
    tool_full_name: str | None,
    payload_enc: bytes,
    payload_hash: str,
    tool_def_hash: str | None,
    expires_at: str,
    created_at: str | None = None,
) -> int:
    stamp = created_at or now_iso()
    with tx() as c:
        cur = c.execute(
            """INSERT INTO pending_actions(
                 user_id, bot_id, kind, server_id, tool_full_name,
                 payload_enc, payload_hash, tool_def_hash, status, result,
                 created_at, expires_at, decided_at
               ) VALUES (?,?,?,?,?,?,?,?, 'pending', NULL,?,?, NULL)""",
            (user_id, bot_id, kind, server_id, tool_full_name,
             payload_enc, payload_hash, tool_def_hash, stamp, expires_at),
        )
        return int(cur.lastrowid)


def get(user_id: int, action_id: int) -> dict | None:
    with tx() as c:
        return _row(c.execute(
            "SELECT * FROM pending_actions WHERE id=? AND user_id=?",
            (action_id, user_id),
        ).fetchone())


def list_for_user(
    user_id: int,
    *,
    status: str | None = "pending",
    bot_id: int | None = None,
    limit: int = 50,
) -> list[dict]:
    limit = max(1, min(int(limit), 100))
    sql = "SELECT * FROM pending_actions WHERE user_id=?"
    args: list = [user_id]
    if status:
        sql += " AND status=?"
        args.append(status)
    if bot_id is not None:
        sql += " AND bot_id=?"
        args.append(bot_id)
    sql += " ORDER BY id DESC LIMIT ?"
    args.append(limit)
    with tx() as c:
        return [_row(r) for r in c.execute(sql, args).fetchall()]


def decide(
    user_id: int,
    action_id: int,
    *,
    from_status: str,
    to_status: str,
    result: str | None = None,
    decided_at: str | None = None,
) -> dict | None:
    """同一事务内改状态；from_status 不匹配则返回 None（并发 / 重复点击）。"""
    stamp = decided_at or now_iso()
    with tx() as c:
        cur = c.execute(
            """UPDATE pending_actions
               SET status=?, result=?, decided_at=?
               WHERE id=? AND user_id=? AND status=?""",
            (to_status, result, stamp, action_id, user_id, from_status),
        )
        if cur.rowcount != 1:
            return None
        return _row(c.execute(
            "SELECT * FROM pending_actions WHERE id=? AND user_id=?",
            (action_id, user_id),
        ).fetchone())


def mark_expired(user_id: int, action_id: int, decided_at: str | None = None) -> dict | None:
    return decide(user_id, action_id, from_status="pending", to_status="expired",
                  result="已过期", decided_at=decided_at)


def detach_for_server(conn, user_id: int, server_id: int, *, stamp: str | None = None) -> int:
    """在删除服务器的同一事务里保留确认历史，取消仍待处理的操作。"""
    stamp = stamp or now_iso()
    cur = conn.execute(
        """UPDATE pending_actions
           SET status='cancelled', result='服务已删除', decided_at=?, server_id=NULL
           WHERE user_id=? AND server_id=? AND status='pending'""",
        (stamp, user_id, server_id),
    )
    cancelled = int(cur.rowcount)
    conn.execute(
        "UPDATE pending_actions SET server_id=NULL WHERE user_id=? AND server_id=?",
        (user_id, server_id),
    )
    return cancelled
