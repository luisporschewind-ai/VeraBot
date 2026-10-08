"""数据访问（Repository）：Bot / 消息 / 用量 / 审计 / Token 预算 等业务查询。"""
import json
from datetime import datetime, timezone

from ..core.tags import coerce_stored_tags
from .database import now_iso, tx


def _bot(r):
    """反序列化权限字段。"""
    if r is None:
        return None
    b = dict(r)
    try:
        b["appearance"] = json.loads(b["appearance"]) if b.get("appearance") else None
    except (ValueError, TypeError):
        b["appearance"] = None
    b["allowed_tools"] = json.loads(b.get("allowed_tools") or "[]")
    b["delegate_to"] = json.loads(b.get("delegate_to") or "[]")
    b["accept_delegation"] = bool(b.get("accept_delegation"))
    b["memory_access"] = b.get("memory_access") or "bot_and_global"
    b["tags"] = coerce_stored_tags(json.loads(b.get("tags") or "[]"))   # 旧数据超出当前上限时按规则收敛
    return b


def get_bot(user_id: int, bot_id: int):
    with tx() as c:
        return _bot(c.execute("SELECT * FROM bots WHERE id=? AND user_id=?", (bot_id, user_id)).fetchone())


def list_bots(user_id: int):
    with tx() as c:
        return [_bot(r) for r in c.execute("SELECT * FROM bots WHERE user_id=? ORDER BY id", (user_id,)).fetchall()]


def audit(user_id: int, bot_id, kind: str, detail: dict):
    """安全审计：越权工具调用 / 被拒绝的委派 / 护栏触发 等。"""
    with tx() as c:
        audit_in(c, user_id, bot_id, kind, detail)


def audit_in(c, user_id: int, bot_id, kind: str, detail: dict):
    """同一连接 / 事务里写审计（db.audit() 另开连接，在未提交的写事务里调用会等锁）。"""
    c.execute("INSERT INTO audit_log(user_id,bot_id,kind,detail,created_at) VALUES (?,?,?,?,?)",
              (user_id, bot_id, kind, json.dumps(detail, ensure_ascii=False), now_iso()))


def day_start_utc(tz_name: str) -> str:
    from zoneinfo import ZoneInfo
    start_local = datetime.now(ZoneInfo(tz_name)).replace(hour=0, minute=0, second=0, microsecond=0)
    return start_local.astimezone(timezone.utc).isoformat(timespec="seconds")


def token_budget(user_id: int) -> tuple[int, int]:
    """返回 (今日已用 tokens, 今日预算)。预算 = users.token_budget 或全局 DAILY_TOKEN_QUOTA。"""
    from ..core.config import DAILY_TOKEN_QUOTA, TIMEZONE
    with tx() as c:
        used = c.execute("SELECT COALESCE(SUM(total_tokens),0) FROM usage_log WHERE user_id=? AND created_at>=?",
                         (user_id, day_start_utc(TIMEZONE))).fetchone()[0]
        b = c.execute("SELECT token_budget FROM users WHERE id=?", (user_id,)).fetchone()
    budget = b[0] if b and b[0] is not None else DAILY_TOKEN_QUOTA
    return int(used), int(budget)


def recent_messages(user_id: int, bot_id: int, limit: int):
    with tx() as c:
        rs = c.execute(
            "SELECT id, role, content, traces FROM messages WHERE user_id=? AND bot_id=? ORDER BY id DESC LIMIT ?",
            (user_id, bot_id, limit),
        ).fetchall()
    return [dict(r) for r in reversed(rs)]


def add_message(user_id, bot_id, role, content, traces=None, memory_ids=None):
    with tx() as c:
        cur = c.execute(
            "INSERT INTO messages(user_id,bot_id,role,content,traces,created_at,memory_ids) VALUES (?,?,?,?,?,?,?)",
            (user_id, bot_id, role, content, json.dumps(traces, ensure_ascii=False) if traces else None, now_iso(),
             json.dumps(memory_ids) if memory_ids else None),
        )
        return cur.lastrowid


def delete_message(user_id: int, bot_id: int, message_id: int) -> bool:
    """删除单条消息（只按 user_id + bot_id + id 命中）；返回是否删到。
    attachments 行随外键 ON DELETE CASCADE 删除；memories / notifications 置 NULL；reminders 由触发器置 NULL。
    （后续可移到 db/message_store.py 的 delete_one()）"""
    with tx() as c:
        return c.execute("DELETE FROM messages WHERE id=? AND user_id=? AND bot_id=?",
                         (message_id, user_id, bot_id)).rowcount > 0


def log_usage(user_id, bot_id, kind, usage: dict | None):
    usage = usage or {}
    with tx() as c:
        c.execute(
            "INSERT INTO usage_log(user_id,bot_id,kind,prompt_tokens,completion_tokens,total_tokens,created_at)"
            " VALUES (?,?,?,?,?,?,?)",
            (user_id, bot_id, kind, int(usage.get("prompt_tokens") or 0),
             int(usage.get("completion_tokens") or 0), int(usage.get("total_tokens") or 0), now_iso()),
        )
