"""记忆服务（Memory service）实现：显式记忆的全部业务规则，不依赖 FastAPI / agents。
包入口 `verabot.services.memory`（__init__.py）原样 re-export 本模块的对外名称，调用方写法不变。

对外：enabled_for / settings / recall / propose / confirm / reject / create / update / delete / clear /
clear_for_bot / list_memories / get_memory / mark_used / bot_counts。错误一律抛 MemoryServiceError（api 层映射 HTTP）。
审计（audit_log）只记 {memory_id, type, scope, bot_id, source, code, ...}，**从不记正文**；日志同样不写正文。
"""
import logging

from ... import db
from ...core import config
from . import policy
from . import repository as repo
from .errors import MemoryServiceError
from .recall import EMPTY, Recall, recall as _recall  # noqa: F401

log = logging.getLogger("verabot.memory")
STATUSES = ("proposed", "candidate", "active", "rejected", "expired")
PENDING = ("proposed", "candidate")
LIVE = ("proposed", "candidate", "active")


def _err(status: int, code: str, **extra) -> MemoryServiceError:
    return MemoryServiceError(status, code, policy.MESSAGES.get(code, code), **extra)


def _audit(c, user_id: int, audit_bot_id, kind: str, **detail):
    """c：当前事务连接（在事务内写审计，避免 SQLite 二次加锁）；None 时单独开事务。"""
    d = {k: v for k, v in detail.items() if v is not None}
    if c is None:
        db.audit(user_id, audit_bot_id, kind, d)
    else:
        db.audit_in(c, user_id, audit_bot_id, kind, d)


# ---------------- 开关 ----------------
def enabled_for(user_id: int) -> bool:
    """VERABOT_MEMORY（运维）且用户总开关打开。"""
    return config.MEMORY_ENABLED and repo.user_enabled(user_id)


def settings(user_id: int) -> dict:
    with db.tx() as c:
        n = repo.active_count(c, user_id)
    return {"enabled": repo.user_enabled(user_id), "server_enabled": config.MEMORY_ENABLED, "active_count": n,
            "max_active": config.MEMORY_MAX_ACTIVE, "max_chars": config.MEMORY_MAX_CHARS}


def set_enabled(user_id: int, enabled: bool) -> dict:
    repo.set_user_enabled(user_id, enabled)
    _audit(None, user_id, None, "memory_settings", enabled=bool(enabled))
    return settings(user_id)


def recall(user_id: int, bot: dict, query_text: str) -> Recall:
    return _recall(user_id, bot, query_text)


def mark_used(user_id: int, ids: list[int]):
    repo.mark_used(user_id, ids)


# ---------------- 序列化 ----------------
def public(r: dict, c=None) -> dict:
    out = {k: r.get(k) for k in ("id", "scope", "bot_id", "bot_name", "type", "source", "source_bot_id",
                                 "source_bot_name", "status", "action", "target_id", "confidence", "use_count",
                                 "last_used_at", "confirmed_at", "expires_at", "created_at", "updated_at")}
    out["content"] = repo.plaintext(r)
    out["sensitivity"] = r.get("sensitivity") or "normal"
    out["sensitive"] = out["sensitivity"] != "normal"
    out["target_content"] = None
    if r.get("target_id"):
        def _target(cc):
            t = repo.get_raw(cc, r_user(r, cc), r["target_id"])
            return repo.plaintext(t) if t else None
        if c is not None:
            out["target_content"] = _target(c)
        else:
            with db.tx() as cc:
                out["target_content"] = _target(cc)
    return out


def r_user(r: dict, c) -> int:
    if "user_id" in r:
        return r["user_id"]
    return repo.owner_of(c, r["id"])


def _load_public(c, user_id: int, mid: int) -> dict:
    r = repo.get(c, user_id, mid)
    if r is None:
        raise _err(404, "not_found")
    r["user_id"] = user_id
    return public(r, c)


# ---------------- 查询 ----------------
def list_memories(user_id: int, *, statuses=("active",), scope: str | None = None, bot_id: int | None = None,
                  ids: list[int] | None = None, visible_to: dict | None = None, limit: int = 200,
                  before_id: int | None = None) -> dict:
    with db.tx() as c:
        repo.expire_stale(c, user_id)
        rs = repo.list_filtered(c, user_id, statuses=statuses, scope=scope, bot_id=bot_id, ids=ids,
                                before_id=before_id, visible_to=visible_to, limit=min(max(limit, 1), 200))
        mems = []
        for r in rs:
            r["user_id"] = user_id
            mems.append(public(r, c))
        cnt = repo.counts(c, user_id)
    return {"memories": mems, "counts": cnt,
            "limits": {"max_active": config.MEMORY_MAX_ACTIVE, "max_chars": config.MEMORY_MAX_CHARS}}


def get_memory(user_id: int, mid: int) -> dict:
    with db.tx() as c:
        repo.expire_stale(c, user_id)
        return _load_public(c, user_id, mid)


def bot_counts(user_id: int) -> dict[int, int]:
    """每个 Bot 可见的生效记忆数（本 Bot 记忆，不含全局）。"""
    with db.tx() as c:
        return repo.bot_active_counts(c, user_id)


# ---------------- 对话中的提议（只由 agents/memory_tools 调用） ----------------
def _visible_active(c, user_id: int, bot: dict, mid) -> dict | None:
    try:
        mid = int(mid)
    except (TypeError, ValueError):
        return None
    r = repo.get_raw(c, user_id, mid)
    if not r or r["status"] != "active":
        return None
    access = bot.get("memory_access") or "none"
    if r["scope"] == "bot" and r["bot_id"] == bot["id"] and access != "none":
        return r
    if r["scope"] == "global" and access == "bot_and_global":
        return r
    return None


def _proposal_result(c, user_id: int, mid: int, note: str | None = None) -> dict:
    m = _load_public(c, user_id, mid)
    out = {"memory_id": m["id"], "status": m["status"], "action": m["action"], "content": m["content"],
           "type": m["type"], "scope": m["scope"], "sensitivity": m["sensitivity"], "sensitive": m["sensitive"],
           "expires_at": m["expires_at"]}
    if m.get("target_id"):
        out["target_id"] = m["target_id"]
        out["target_content"] = m["target_content"]
    out["note"] = note or "已向用户显示确认卡片，等待用户点按确认；用户确认前没有保存，不要声称已经记住"
    return out


def _blocked(c, user_id: int, bot: dict, code: str, **detail) -> dict:
    log.info("memory blocked: user=%s bot=%s code=%s", user_id, bot.get("id"), code)   # 不写正文
    _audit(c, user_id, bot.get("id"), "memory_blocked", code=code, **detail)
    msg = policy.MESSAGES.get(code, code)
    if code in ("sensitive_credential", "sensitive_category", "blocked_content"):
        msg += "。请向用户说明这类信息不会被保存，不要再次尝试"
    return {"error": msg, "code": code}


def propose(user_id: int, bot: dict, turn, *, action: str, content: str = "", type: str = "fact",
            scope: str = "global", target_id=None, user_message_id: int | None = None) -> dict:
    """生成「待确认」提议（status=proposed）。检查顺序见 MEMORY_GROWTH §5.2。返回值同时是 tool result 与 trace。"""
    if not enabled_for(user_id):
        return {"error": policy.MESSAGES["memory_disabled"], "code": "memory_disabled"}
    if turn.memory_proposals >= config.MEMORY_PROPOSALS_PER_TURN:
        return {"error": policy.MESSAGES["proposal_cap"], "code": "proposal_cap"}
    turn.memory_proposals += 1
    access = bot.get("memory_access") or "none"
    if access == "none":
        return {"error": "这个 Bot 未开启记忆", "code": "memory_disabled"}

    with db.tx() as c:
        repo.expire_stale(c, user_id)
        if action == "delete":
            target = _visible_active(c, user_id, bot, target_id)
            if target is None:
                return {"error": policy.MESSAGES["not_found"], "code": "not_found"}
            h = f"delete:{target['id']}"
            dup = repo.find_by_hash(c, user_id, target["scope"], target["bot_id"], h, PENDING, "delete")
            if dup:
                return _proposal_result(c, user_id, dup["id"])
            mid = repo.insert(c, user_id=user_id, scope=target["scope"], bot_id=target["bot_id"], type=target["type"],
                              content="", content_hash=h, source="explicit_chat", source_bot_id=bot["id"],
                              source_message_id=user_message_id, status="proposed", action="delete",
                              target_id=target["id"], sensitivity="normal",
                              expires_at=repo.iso_in(config.MEMORY_PROPOSAL_TTL_DAYS))
            _audit(c, user_id, bot["id"], "memory_proposed", memory_id=mid, action="delete", target_id=target["id"],
                   scope=target["scope"], source="explicit_chat")
            return _proposal_result(c, user_id, mid, "已向用户显示「要忘掉这条吗？」确认卡片；用户确认前记忆仍然保留")

        text = policy.clean(content)
        code, sensitivity = policy.check(text)
        mtype = type if type in policy.TYPES_M1 else "fact"
        if code:
            return _blocked(c, user_id, bot, code, type=mtype, scope=scope)
        if scope not in policy.SCOPES_WRITABLE:
            scope = "global"
        if scope == "global" and access != "bot_and_global":
            scope = "bot"                                   # memory_access=bot：降为本 Bot 记忆
        bot_id = bot["id"] if scope == "bot" else None
        target = None
        if target_id is not None:
            target = _visible_active(c, user_id, bot, target_id)
            if target is None:
                return {"error": policy.MESSAGES["not_found"], "code": "not_found"}
        h = policy.content_hash(text, sensitivity)
        known = repo.find_by_hash(c, user_id, scope, bot_id, h, ("active",))
        if known:
            return {"status": "already_known", "memory_id": known["id"],
                    "note": "这条信息已经在记忆中，不需要再记，也不要再询问用户"}
        cutoff = repo.iso_in(-config.MEMORY_REJECT_COOLDOWN_DAYS)
        declined = repo.recently_declined(c, user_id, scope, bot_id, h, cutoff)
        if declined:
            return {"status": "previously_declined",
                    "note": "用户最近拒绝过记住这条信息，不要再提议，也不要再询问"}
        act = "update" if target else "create"
        if act == "create" and repo.active_count(c, user_id) >= config.MEMORY_MAX_ACTIVE:
            return {"error": policy.MESSAGES["memory_limit"], "code": "memory_limit"}
        dup = repo.find_by_hash(c, user_id, scope, bot_id, h, PENDING, act)
        if dup:
            return _proposal_result(c, user_id, dup["id"])
        col, enc = repo.stored(text, sensitivity)
        mid = repo.insert(c, user_id=user_id, scope=scope, bot_id=bot_id, type=mtype, content=col, content_enc=enc,
                          content_hash=h, source="explicit_chat", source_bot_id=bot["id"],
                          source_message_id=user_message_id, status="proposed", action=act,
                          target_id=target["id"] if target else None, sensitivity=sensitivity,
                          expires_at=repo.iso_in(config.MEMORY_PROPOSAL_TTL_DAYS))
        _audit(c, user_id, bot["id"], "memory_proposed", memory_id=mid, action=act, type=mtype, scope=scope,
               bot_id=bot_id, source="explicit_chat", sensitivity=sensitivity if sensitivity != "normal" else None)
        log.info("memory proposed: user=%s bot=%s id=%s action=%s type=%s", user_id, bot["id"], mid, act, mtype)
        return _proposal_result(c, user_id, mid)


# ---------------- 用户操作（HTTP） ----------------
def _check_text(text: str) -> tuple[str, str]:
    t = policy.clean(text)
    code, sensitivity = policy.check(t)
    if code:
        raise _err(422, code)
    return t, sensitivity


def _expire_if_stale(user_id: int, mid: int):
    """单独提交的事务：确认 / 拒绝前先把已超时的提议置为 expired（之后再返回 410，过期状态不会被回滚）。"""
    with db.tx() as c:
        r = repo.get_raw(c, user_id, mid)
        if r and r["status"] in PENDING and r["expires_at"] and r["expires_at"] < db.now_iso():
            repo.update(c, user_id, mid, status="expired", content="", content_enc=None)
            _audit(c, user_id, r["source_bot_id"], "memory_expired", memory_id=mid)


def _pending_row(c, user_id: int, mid: int) -> dict:
    r = repo.get_raw(c, user_id, mid)
    if r is None:
        raise _err(404, "not_found")
    if r["status"] == "expired":
        raise MemoryServiceError(410, "expired", "这条提议已过期")
    if r["status"] not in PENDING:
        raise MemoryServiceError(409, "already_handled", "这条提议已处理过", current_status=r["status"])
    return r


def confirm(user_id: int, mid: int, content: str | None = None) -> dict:
    _expire_if_stale(user_id, mid)
    with db.tx() as c:
        r = _pending_row(c, user_id, mid)
        if r["action"] == "delete":
            tid = r["target_id"]
            repo.delete(c, user_id, tid)          # 级联删除提议本身（target_id ON DELETE CASCADE）
            repo.delete(c, user_id, mid)
            _audit(c, user_id, r["source_bot_id"], "memory_confirmed", memory_id=mid, action="delete", target_id=tid)
            _audit(c, user_id, r["source_bot_id"], "memory_deleted", memory_id=tid, source="forget_memory")
            return {"ok": True, "deleted_id": tid}
        cols = {}
        sensitivity = r["sensitivity"]
        h = r["content_hash"]
        if content is not None:
            text, sensitivity = _check_text(content)
            h = policy.content_hash(text, sensitivity)
            col, enc = repo.stored(text, sensitivity)
            cols.update(content=col, content_enc=enc, content_hash=h, sensitivity=sensitivity)
        existing = repo.find_by_hash(c, user_id, r["scope"], r["bot_id"], h, ("active",), exclude_id=mid)
        if existing:
            repo.delete(c, user_id, mid)
            _audit(c, user_id, r["source_bot_id"], "memory_confirmed", memory_id=existing["id"], code="duplicate")
            return _load_public(c, user_id, existing["id"])
        if r["action"] == "create" and repo.active_count(c, user_id) >= config.MEMORY_MAX_ACTIVE:
            raise _err(400, "memory_limit")
        tid = r["target_id"] if r["action"] == "update" else None
        cols.update(status="active", confirmed_at=db.now_iso(), expires_at=None, action="create", target_id=None)
        try:
            repo.update(c, user_id, mid, **cols)
        except Exception as e:   # 唯一索引冲突（并发确认同一内容）
            raise MemoryServiceError(409, "duplicate", "已有相同的记忆") from e
        if tid:
            repo.delete(c, user_id, tid)
        _audit(c, user_id, r["source_bot_id"], "memory_confirmed", memory_id=mid, action=r["action"], type=r["type"],
               scope=r["scope"], bot_id=r["bot_id"], replaced_id=tid, edited=content is not None or None)
        return _load_public(c, user_id, mid)


def reject(user_id: int, mid: int) -> dict:
    _expire_if_stale(user_id, mid)
    with db.tx() as c:
        r = _pending_row(c, user_id, mid)
        if r["action"] == "delete":
            repo.delete(c, user_id, mid)
        else:
            repo.update(c, user_id, mid, status="rejected", content="", content_enc=None, target_id=None)
        _audit(c, user_id, r["source_bot_id"], "memory_rejected", memory_id=mid, action=r["action"], type=r["type"],
               scope=r["scope"])
    return {"ok": True}


def _resolve_scope(user_id: int, scope: str, bot_id: int | None) -> int | None:
    if scope not in policy.SCOPES_WRITABLE:
        raise _err(422, "invalid_scope")
    if scope == "global":
        return None
    if bot_id is None:
        raise MemoryServiceError(422, "invalid_scope", "「仅某个 Bot」需要指定 Bot")
    if not db.get_bot(user_id, bot_id):
        raise MemoryServiceError(404, "bot_not_found", "Bot 不存在")
    return bot_id


def create(user_id: int, *, content: str, type: str, scope: str, bot_id: int | None = None) -> dict:
    """记忆页手动添加：用户亲手输入即视为确认 → 直接 active，source=memory_page。"""
    if type not in policy.TYPES_M1:
        raise MemoryServiceError(422, "invalid_type", "类型只能是 资料 / 偏好 / 事实")
    bid = _resolve_scope(user_id, scope, bot_id)
    text, sensitivity = _check_text(content)
    h = policy.content_hash(text, sensitivity)
    with db.tx() as c:
        dup = repo.find_by_hash(c, user_id, scope, bid, h, ("active",))
        if dup:
            raise MemoryServiceError(409, "duplicate", "已有相同的记忆", memory_id=dup["id"])
        if repo.active_count(c, user_id) >= config.MEMORY_MAX_ACTIVE:
            raise _err(400, "memory_limit")
        col, enc = repo.stored(text, sensitivity)
        now = db.now_iso()
        mid = repo.insert(c, user_id=user_id, scope=scope, bot_id=bid, type=type, content=col, content_enc=enc,
                          content_hash=h, source="memory_page", status="active", sensitivity=sensitivity,
                          confirmed_at=now)
        _audit(c, user_id, bid, "memory_created", memory_id=mid, type=type, scope=scope, bot_id=bid, source="memory_page")
        return _load_public(c, user_id, mid)


def update(user_id: int, mid: int, *, content: str | None = None, type: str | None = None,
           scope: str | None = None, bot_id: int | None = None) -> dict:
    with db.tx() as c:
        r = repo.get_raw(c, user_id, mid)
        if r is None:
            raise _err(404, "not_found")
        if r["status"] != "active":
            raise MemoryServiceError(409, "not_active", "只能编辑已生效的记忆", current_status=r["status"])
        cols = {}
        new_scope = scope or r["scope"]
        if r["scope"] == "summary" or new_scope == "summary":
            raise MemoryServiceError(422, "invalid_scope", "对话摘要不能编辑")
        if type is not None:
            if type not in policy.TYPES_M1:
                raise MemoryServiceError(422, "invalid_type", "类型只能是 资料 / 偏好 / 事实")
            cols["type"] = type
        new_bot = r["bot_id"]
        if scope is not None or bot_id is not None:
            new_bot = _resolve_scope(user_id, new_scope, bot_id if bot_id is not None else (r["bot_id"] if new_scope == "bot" else None))
            cols.update(scope=new_scope, bot_id=new_bot)
        h, sensitivity = r["content_hash"], r["sensitivity"]
        if content is not None:
            text, sensitivity = _check_text(content)
            h = policy.content_hash(text, sensitivity)
            col, enc = repo.stored(text, sensitivity)
            cols.update(content=col, content_enc=enc, content_hash=h, sensitivity=sensitivity)
        if repo.find_by_hash(c, user_id, new_scope, new_bot, h, LIVE, "create", exclude_id=mid):
            raise MemoryServiceError(409, "duplicate", "已有相同的记忆")
        if cols:
            repo.update(c, user_id, mid, **cols)
            _audit(c, user_id, new_bot, "memory_updated", memory_id=mid, type=cols.get("type"), scope=new_scope,
                   bot_id=new_bot, fields=sorted(k for k in cols if k not in ("content_enc", "content_hash")))
        return _load_public(c, user_id, mid)


def delete(user_id: int, mid: int) -> dict:
    with db.tx() as c:
        r = repo.get_raw(c, user_id, mid)
        if r is None:
            raise _err(404, "not_found")
        repo.delete(c, user_id, mid)
        _audit(c, user_id, r["bot_id"], "memory_deleted", memory_id=mid, type=r["type"], scope=r["scope"], source="memory_page")
    return {"ok": True}


def clear(user_id: int, scope: str, bot_id: int | None = None) -> int:
    """清空：all = 本人全部（含待确认 / 已拒绝）；global；bot / summary 需 bot_id。物理删除。"""
    if scope not in ("all", "global", "bot", "summary"):
        raise _err(422, "invalid_scope")
    with db.tx() as c:
        if scope == "all":
            n = repo.delete_all(c, user_id)
        elif scope == "global":
            n = repo.delete_global(c, user_id)
        else:
            if bot_id is None:
                raise MemoryServiceError(422, "invalid_scope", "需要指定 bot_id")
            if not db.get_bot(user_id, bot_id):
                raise MemoryServiceError(404, "bot_not_found", "Bot 不存在")
            n = repo.delete_scope(c, user_id, scope, bot_id)
    _audit(None, user_id, bot_id, "memory_cleared", scope=scope, bot_id=bot_id, deleted=n)
    return n


def clear_for_bot(user_id: int, bot_id: int) -> int:
    """清空对话时可选：删除该 Bot 的 bot 记忆与对话摘要（全局资料保留）。"""
    with db.tx() as c:
        n = repo.delete_for_bot(c, user_id, bot_id)
    _audit(None, user_id, bot_id, "memory_cleared", scope="bot+summary", bot_id=bot_id, deleted=n, source="clear_chat")
    return n
