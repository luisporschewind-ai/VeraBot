"""memories 表 SQL。每条语句都带 user_id（租户隔离）；他人与不存在统一视为「不存在」。"""
import json
from datetime import datetime, timedelta, timezone

from ... import db
from ...core import crypto
from .policy import SENSITIVE_PLACEHOLDER

COLS = ("m.id, m.scope, m.bot_id, b.name AS bot_name, m.type, m.content, m.content_enc, m.sensitivity, m.source, "
        "m.source_bot_id, sb.name AS source_bot_name, m.status, m.action, m.target_id, m.confidence, m.use_count, "
        "m.last_used_at, m.confirmed_at, m.expires_at, m.created_at, m.updated_at")
FROM = "FROM memories m LEFT JOIN bots b ON b.id=m.bot_id LEFT JOIN bots sb ON sb.id=m.source_bot_id"


def iso_in(days: float) -> str:
    return (datetime.now(timezone.utc) + timedelta(days=days)).isoformat(timespec="seconds")


def plaintext(r: dict) -> str:
    """正文明文：敏感记忆解密（密钥丢失时返回占位文字，不抛错）。"""
    if r.get("sensitivity", "normal") != "normal" and r.get("content_enc"):
        return crypto.decrypt(r["content_enc"]) or "[无法解密：密钥缺失或已更换]"
    return r.get("content") or ""


def stored(content: str, sensitivity: str) -> tuple[str, str | None]:
    """→ (content 列, content_enc 列)。敏感记忆的明文只以密文形式落库。"""
    if sensitivity != "normal":
        return SENSITIVE_PLACEHOLDER[sensitivity], crypto.encrypt(content)
    return content, None


def expire_stale(c, user_id: int):
    """惰性过期：proposed / candidate 超过有效期 → expired，清空正文。"""
    c.execute("UPDATE memories SET status='expired', content='', content_enc=NULL, updated_at=? "
              "WHERE user_id=? AND status IN ('proposed','candidate') AND expires_at IS NOT NULL AND expires_at<?",
              (db.now_iso(), user_id, db.now_iso()))


def get(c, user_id: int, mid: int) -> dict | None:
    return db.row(c.execute(f"SELECT {COLS} {FROM} WHERE m.user_id=? AND m.id=?", (user_id, mid)).fetchone())


def get_raw(c, user_id: int, mid: int) -> dict | None:
    return db.row(c.execute("SELECT * FROM memories WHERE user_id=? AND id=?", (user_id, mid)).fetchone())


def query(c, user_id: int, where: str = "", params: tuple = (), order: str = "m.id DESC", limit: int = 200) -> list[dict]:
    sql = f"SELECT {COLS} {FROM} WHERE m.user_id=?" + (f" AND ({where})" if where else "") + f" ORDER BY {order} LIMIT ?"
    return db.rows(c.execute(sql, (user_id, *params, limit)).fetchall())


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
    return db.row(c.execute(sql + " ORDER BY id DESC LIMIT 1", params).fetchone())


def active_count(c, user_id: int) -> int:
    return c.execute("SELECT COUNT(*) FROM memories WHERE user_id=? AND status='active' AND scope IN ('global','bot')",
                     (user_id,)).fetchone()[0]


def insert(c, **cols) -> int:
    now = db.now_iso()
    cols.setdefault("created_at", now)
    cols.setdefault("updated_at", now)
    return c.execute(f"INSERT INTO memories({','.join(cols)}) VALUES ({','.join('?' * len(cols))})",
                     tuple(cols.values())).lastrowid


def update(c, user_id: int, mid: int, **cols):
    cols["updated_at"] = db.now_iso()
    c.execute(f"UPDATE memories SET {','.join(f'{k}=?' for k in cols)} WHERE user_id=? AND id=?",
              (*cols.values(), user_id, mid))


def delete(c, user_id: int, mid: int) -> int:
    return c.execute("DELETE FROM memories WHERE user_id=? AND id=?", (user_id, mid)).rowcount


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
    with db.tx() as c:
        c.execute(f"UPDATE memories SET use_count=use_count+1, last_used_at=? WHERE user_id=? "
                  f"AND id IN ({','.join('?' * len(ids))})", (db.now_iso(), user_id, *ids))


def user_enabled(user_id: int) -> bool:
    with db.tx() as c:
        r = c.execute("SELECT memory_enabled FROM users WHERE id=?", (user_id,)).fetchone()
    return bool(r and r[0])


def set_user_enabled(user_id: int, enabled: bool):
    with db.tx() as c:
        c.execute("UPDATE users SET memory_enabled=? WHERE id=?", (int(enabled), user_id))


def dumps(v) -> str:
    return json.dumps(v, ensure_ascii=False)
