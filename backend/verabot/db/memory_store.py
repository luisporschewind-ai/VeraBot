"""memories 表（以及 users.memory_enabled 开关）的 SQL。

每条语句都带 user_id（租户隔离）；他人与不存在统一视为「不存在」。
业务规则（加密 / 占位文字 / 去重策略）留在 services/memory；这里只放 SQL，调用方传入同一条连接以保持事务。
"""
from __future__ import annotations

from .database import now_iso, row, rows, tx

COLS = ("m.id, m.scope, m.bot_id, b.name AS bot_name, m.type, m.content, m.content_enc, m.sensitivity, m.source, "
        "m.source_bot_id, sb.name AS source_bot_name, m.status, m.action, m.target_id, m.confidence, m.use_count, "
        "m.last_used_at, m.confirmed_at, m.expires_at, m.created_at, m.updated_at")
FROM = "FROM memories m LEFT JOIN bots b ON b.id=m.bot_id LEFT JOIN bots sb ON sb.id=m.source_bot_id"


def expire_stale(c, user_id: int):
    """惰性过期：proposed / candidate 超过有效期 → expired，清空正文。"""
    c.execute("UPDATE memories SET status='expired', content='', content_enc=NULL, updated_at=? "
              "WHERE user_id=? AND status IN ('proposed','candidate') AND expires_at IS NOT NULL AND expires_at<?",
              (now_iso(), user_id, now_iso()))


def get(c, user_id: int, mid: int) -> dict | None:
    return row(c.execute(f"SELECT {COLS} {FROM} WHERE m.user_id=? AND m.id=?", (user_id, mid)).fetchone())


def get_raw(c, user_id: int, mid: int) -> dict | None:
    return row(c.execute("SELECT * FROM memories WHERE user_id=? AND id=?", (user_id, mid)).fetchone())


def owner_of(c, mid: int) -> int:
    """记忆所属 user_id（调用方已确认该行存在）。"""
    return c.execute("SELECT user_id FROM memories WHERE id=?", (mid,)).fetchone()[0]


def query(c, user_id: int, where: str = "", params: tuple = (), order: str = "m.id DESC", limit: int = 200) -> list[dict]:
    sql = f"SELECT {COLS} {FROM} WHERE m.user_id=?" + (f" AND ({where})" if where else "") + f" ORDER BY {order} LIMIT ?"
    return rows(c.execute(sql, (user_id, *params, limit)).fetchall())


def list_filtered(c, user_id: int, *, statuses, scope: str | None, bot_id: int | None, ids, before_id,
                  visible_to: dict | None, limit: int) -> list[dict]:
    """记忆页 / 工具列表的过滤查询。visible_to：只返回该 Bot 按 memory_access 可见的记忆。"""
    where, params = [f"m.status IN ({','.join('?' * len(statuses))})"], list(statuses)
    if scope:
        where.append("m.scope=?"); params.append(scope)
    if bot_id is not None:
        where.append("m.bot_id=?"); params.append(bot_id)
    if ids:
        where.append(f"m.id IN ({','.join('?' * len(ids))})"); params.extend(ids)
    if before_id:
        where.append("m.id<?"); params.append(before_id)
    if visible_to is not None:
        access = visible_to.get("memory_access") or "none"
        if access == "none":
            where.append("0")
        elif access == "bot":
            where.append("m.scope IN ('bot','summary') AND m.bot_id=?"); params.append(visible_to["id"])
        else:
            where.append("(m.scope='global' OR (m.scope IN ('bot','summary') AND m.bot_id=?))"); params.append(visible_to["id"])
    return query(c, user_id, " AND ".join(where), tuple(params), limit=limit)


def visible_active(c, user_id: int, bot_id: int, include_global: bool, limit: int) -> list[dict]:
    """召回用：本 Bot 的生效 bot 记忆 +（include_global 时）全局资料，按更新时间倒序。"""
    where = "m.status='active' AND ((m.scope='bot' AND m.bot_id=?)"
    params: list = [bot_id]
    if include_global:
        where += " OR m.scope='global'"
    where += ")"
    return query(c, user_id, where, tuple(params), order="m.updated_at DESC", limit=limit)


def active_summary(c, user_id: int, bot_id: int) -> dict | None:
    """该 Bot 的滚动摘要（scope='summary'，每个 Bot 至多一条 active）。召回不走 visible_active，单独取。"""
    return row(c.execute(f"SELECT {COLS} {FROM} WHERE m.user_id=? AND m.scope='summary' AND m.bot_id=? "
                         f"AND m.status='active' ORDER BY m.id DESC LIMIT 1", (user_id, bot_id)).fetchone())


def find_by_hash(c, user_id: int, scope: str, bot_id, h: str, statuses: tuple, action: str | None = None,
                 exclude_id: int | None = None) -> dict | None:
    sql = (f"SELECT * FROM memories WHERE user_id=? AND scope=? AND COALESCE(bot_id,0)=? AND content_hash=? "
           f"AND status IN ({','.join('?' * len(statuses))})")
    params = [user_id, scope, bot_id or 0, h, *statuses]
    if action:
        sql += " AND action=?"
        params.append(action)
    if exclude_id:
        sql += " AND id<>?"
        params.append(exclude_id)
    return row(c.execute(sql + " ORDER BY id DESC LIMIT 1", params).fetchone())


def recently_declined(c, user_id: int, scope: str, bot_id, h: str, cutoff: str):
    """冷却期内被拒绝过的同内容记忆（有则返回一行，否则 None）。"""
    return c.execute("SELECT id FROM memories WHERE user_id=? AND scope=? AND COALESCE(bot_id,0)=? AND content_hash=? "
                     "AND status='rejected' AND updated_at>=? LIMIT 1", (user_id, scope, bot_id or 0, h, cutoff)).fetchone()


def active_count(c, user_id: int) -> int:
    return c.execute("SELECT COUNT(*) FROM memories WHERE user_id=? AND status='active' AND scope IN ('global','bot')",
                     (user_id,)).fetchone()[0]


def insert(c, **cols) -> int:
    now = now_iso()
    cols.setdefault("created_at", now)
    cols.setdefault("updated_at", now)
    return c.execute(f"INSERT INTO memories({','.join(cols)}) VALUES ({','.join('?' * len(cols))})",
                     tuple(cols.values())).lastrowid


def update(c, user_id: int, mid: int, **cols):
    cols["updated_at"] = now_iso()
    c.execute(f"UPDATE memories SET {','.join(f'{k}=?' for k in cols)} WHERE user_id=? AND id=?",
              (*cols.values(), user_id, mid))


def delete(c, user_id: int, mid: int) -> int:
    return c.execute("DELETE FROM memories WHERE user_id=? AND id=?", (user_id, mid)).rowcount


def delete_all(c, user_id: int) -> int:
    return c.execute("DELETE FROM memories WHERE user_id=?", (user_id,)).rowcount


def delete_global(c, user_id: int) -> int:
    return c.execute("DELETE FROM memories WHERE user_id=? AND scope='global'", (user_id,)).rowcount


def delete_scope(c, user_id: int, scope: str, bot_id: int) -> int:
    return c.execute("DELETE FROM memories WHERE user_id=? AND scope=? AND bot_id=?", (user_id, scope, bot_id)).rowcount


def delete_for_bot(c, user_id: int, bot_id: int) -> int:
    """该 Bot 的 bot 记忆与对话摘要（全局资料保留）。"""
    return c.execute("DELETE FROM memories WHERE user_id=? AND bot_id=? AND scope IN ('bot','summary')",
                     (user_id, bot_id)).rowcount


def bot_active_counts(c, user_id: int) -> dict:
    """{bot_id: 生效 bot 记忆数}（键为 int）。"""
    return {k: v for k, v in c.execute(
        "SELECT bot_id, COUNT(*) FROM memories WHERE user_id=? AND status='active' AND scope='bot' GROUP BY bot_id",
        (user_id,)).fetchall()}


def counts(c, user_id: int) -> dict:
    by_status = dict(c.execute("SELECT status, COUNT(*) FROM memories WHERE user_id=? AND scope IN ('global','bot') "
                               "GROUP BY status", (user_id,)).fetchall())
    by_bot = {str(k): v for k, v in c.execute(
        "SELECT bot_id, COUNT(*) FROM memories WHERE user_id=? AND status='active' AND scope='bot' GROUP BY bot_id",
        (user_id,)).fetchall()}
    glob = c.execute("SELECT COUNT(*) FROM memories WHERE user_id=? AND status='active' AND scope='global'",
                     (user_id,)).fetchone()[0]
    return {"active": by_status.get("active", 0), "proposed": by_status.get("proposed", 0),
            "candidate": by_status.get("candidate", 0), "global": glob, "by_bot": by_bot}


def mark_used(user_id: int, ids: list[int]):
    if not ids:
        return
    with tx() as c:
        c.execute(f"UPDATE memories SET use_count=use_count+1, last_used_at=? WHERE user_id=? "
                  f"AND id IN ({','.join('?' * len(ids))})", (now_iso(), user_id, *ids))


def user_enabled(user_id: int) -> bool:
    with tx() as c:
        r = c.execute("SELECT memory_enabled FROM users WHERE id=?", (user_id,)).fetchone()
    return bool(r and r[0])


def set_user_enabled(user_id: int, enabled: bool):
    with tx() as c:
        c.execute("UPDATE users SET memory_enabled=? WHERE id=?", (int(enabled), user_id))
