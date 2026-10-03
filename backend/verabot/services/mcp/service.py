"""把目录、HTTP 客户端和数据库接在一起，给 API 与 Agent 用。"""
from __future__ import annotations

import hashlib
import json
import logging
import os
import random
import threading
import time
from datetime import datetime, timedelta, timezone

from ... import db
from ...core.config import (
    MCP_BREAKER_COOLDOWN_DEFAULT,
    MCP_BREAKER_THRESHOLD_DEFAULT,
    MCP_RETRY_BACKOFF_DEFAULT,
    MCP_RETRY_MAX_DEFAULT,
)
from ...db import mcp_store
from . import catalog, sync
from .http_client import (
    MCPClientError,
    MCPProtocolError,
    MCPRPCError,
    MCPSessionExpiredError,
    MCPTimeoutError,
    MCPUnavailableError,
    borrow_session,
    drop_session,
    timeout_seconds,
)
from .naming import strip_extensions
from .sanitize import clean_description, wrap

log = logging.getLogger("verabot.mcp")

# 后台同步：同一 (user, server) 同时只跑一个。显式 POST /sync 会排队再跑一遍。
_INFLIGHT: set[tuple[int, int]] = set()
_INFLIGHT_LOCK = threading.Lock()
_SERVER_LOCKS: dict[tuple[int, int], threading.Lock] = {}

_CONSENT_MESSAGE = "尚未同意把这个 MCP 服务的工具结果发送给 DeepSeek，因此没有调用它。请在设置里同意后再试。"
_CIRCUIT_MESSAGE = "这个 MCP 服务连续失败，已暂时停止连接。请稍后再试。"
_UNKNOWN_MESSAGE = "请求可能已执行，也可能没有。请到对应服务核实。"


def public_catalog() -> list[dict]:
    out = []
    for item in catalog.entries():
        out.append({
            "catalog_id": item["catalog_id"],
            "slug": item["slug"],
            "name": item["name"],
            "description": item["description"],
            "trust": item["trust"],
            "transport": item["transport"],
            "auth": item["auth"],
            "enabled_by_default": item["enabled_by_default"],
            "url_configured": bool(item["url"]),
        })
    return out


def _as_utc(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def circuit_state(row: dict, now: datetime | None = None) -> str:
    """closed / open / half_open。open_until 未到是打开；到了但失败计数还在，是半开（下一次请求作为探测）。"""
    now = now or datetime.now(timezone.utc)
    until = _as_utc(row.get("circuit_open_until"))
    failures = int(row.get("circuit_failures") or 0)
    if until and until > now:
        return "open"
    if until and failures > 0:
        return "half_open"
    return "closed"


def public_server(row: dict) -> dict:
    return {
        "id": row["id"],
        "slug": row["slug"],
        "catalog_id": row.get("catalog_id"),
        "name": row["name"],
        "source": row["source"],
        "transport": row["transport"],
        "trust": row["trust"],
        "auth_type": row["auth_type"],
        "status": row["status"],
        "enabled": row["status"] != "disabled",
        "account_label": row.get("account_label"),
        "tools_count": mcp_store.tool_count(row["user_id"], row["id"]),
        "last_error": row.get("last_error"),
        "last_synced_at": row.get("last_synced_at"),
        "consent_at": row.get("consent_at"),
        "sync_status": row.get("sync_status") or "pending",
        "circuit_state": circuit_state(row),
        "circuit_open_until": row.get("circuit_open_until"),
        "consecutive_failures": int(row.get("circuit_failures") or 0),
    }


def public_tool(row: dict) -> dict:
    title = row.get("title")
    return {
        "id": row["id"],
        "server_id": row["server_id"],
        "full_name": row["full_name"],
        "mcp_name": row["mcp_name"],
        "label": catalog.label_for(row["mcp_name"], title),
        "description": row.get("description") or "",
        "risk": row["risk"],
        "requires_confirmation": row["risk"] != "read",
        "delegable": False,
        "status": row["status"],
        "annotations": row.get("annotations"),
    }


def tool_schema(row: dict, server_name: str) -> dict:
    """给模型的 function schema。描述带来源前缀，并视为不可信。"""
    return {
        "type": "function",
        "function": {
            "name": row["full_name"],
            "description": clean_description(server_name, row.get("description") or ""),
            "parameters": strip_extensions(row.get("input_schema") or {"type": "object", "properties": {}}),
        },
    }


def ensure_servers(user_id: int) -> list[dict]:
    """补齐目录里的服务。不在这个请求里访问网络；默认开启且还没同步过的，放到后台同步。"""
    for spec in catalog.entries():
        row = mcp_store.get_server_by_slug(user_id, spec["slug"])
        if row is None:
            status = "disabled" if not spec["enabled"] else "needs_auth"
            row = mcp_store.insert_server(user_id, spec, status)
            db.audit(user_id, None, "mcp_server_added", {
                "slug": spec["slug"], "source": "catalog", "catalog_id": spec["catalog_id"],
            })
        if _should_schedule(row, spec):
            schedule_sync(user_id, row["id"])
    return [public_server(row) for row in mcp_store.list_servers(user_id)]


def _should_schedule(row: dict, spec: dict | None) -> bool:
    if row["status"] == "disabled":
        return False
    if (row.get("sync_status") or "pending") != "pending":
        return False
    url = ((spec or {}).get("url") or row.get("url") or "")
    return bool(url)


def schedule_sync(user_id: int, server_id: int) -> bool:
    """启动后台同步。已经在跑就不再开第二个。返回是否新启动了。"""
    key = (user_id, server_id)
    with _INFLIGHT_LOCK:
        if key in _INFLIGHT:
            return False
        _INFLIGHT.add(key)
    mcp_store.update_server(user_id, server_id, sync_status="syncing")

    def run():
        try:
            sync_server(user_id, server_id)
        except Exception:
            log.exception("mcp background sync failed user=%s server=%s", user_id, server_id)
            try:
                mcp_store.update_server(
                    user_id, server_id, status="error", sync_status="error", last_error="同步失败",
                )
            except Exception:
                log.exception("mcp background sync could not record failure")
        finally:
            with _INFLIGHT_LOCK:
                _INFLIGHT.discard(key)

    threading.Thread(target=run, name=f"mcp-sync-{user_id}-{server_id}", daemon=True).start()
    return True


def sync_server(user_id: int, server_id: int) -> dict:
    """阻塞式同步。手动刷新走这里；后台线程也走这里，用同一把锁避免交错。"""
    with _server_lock((user_id, server_id)):
        return _sync_body(user_id, server_id)


def _server_lock(key: tuple[int, int]) -> threading.Lock:
    with _INFLIGHT_LOCK:
        lock = _SERVER_LOCKS.get(key)
        if lock is None:
            lock = threading.Lock()
            _SERVER_LOCKS[key] = lock
        return lock


def _sync_body(user_id: int, server_id: int) -> dict:
    row = mcp_store.get_server(user_id, server_id)
    if row is None:
        raise KeyError(server_id)
    spec = catalog.by_id(row.get("catalog_id") or "") or catalog.by_slug(row["slug"])
    url = (spec or {}).get("url") or row.get("url") or ""
    if row["status"] == "disabled":
        if row.get("sync_status") == "syncing":
            row = mcp_store.update_server(user_id, server_id, sync_status="pending")
        return {**_empty_summary(), "server": public_server(row)}
    if circuit_state(row) == "open":
        fresh = mcp_store.update_server(
            user_id, server_id, sync_status="error", last_error=_CIRCUIT_MESSAGE,
        )
        return {**_empty_summary(), "server": public_server(fresh)}
    if not url:
        fresh = mcp_store.update_server(
            user_id, server_id, status="error", sync_status="error",
            last_error="尚未配置 MCP 服务地址", url=None,
        )
        return {**_empty_summary(), "server": public_server(fresh)}
    mcp_store.update_server(user_id, server_id, sync_status="syncing", url=url)
    try:
        session = borrow_session((user_id, server_id), url, timeout_seconds())
        tools = _with_retries(session.list_tools, idempotent=True)
        summary = sync.apply(user_id, row, tools)
        _record_success(user_id, server_id)
        current = mcp_store.get_server(user_id, server_id) or row
        fields = {"url": url, "last_error": None, "last_synced_at": db.now_iso(), "sync_status": "ok"}
        # 同步过程中用户可能已经停用。停用优先，不要被这次结果改回已连接。
        if current.get("status") != "disabled":
            fields["status"] = "connected"
        fresh = mcp_store.update_server(user_id, server_id, **fields)
    except MCPClientError as exc:
        if _counts_toward_breaker(exc):
            _record_failure(user_id, server_id)
        fresh = mcp_store.update_server(
            user_id, server_id, status="error", url=url, sync_status="error",
            last_error=_safe_error(exc),
        )
        summary = _empty_summary()
    return {**summary, "server": public_server(fresh)}


def set_enabled(user_id: int, server_id: int, enabled: bool) -> dict:
    row = mcp_store.get_server(user_id, server_id)
    if row is None:
        raise KeyError(server_id)
    if not enabled:
        fresh = mcp_store.update_server(user_id, server_id, status="disabled")
        db.audit(user_id, None, "mcp_server_disabled", {"slug": row["slug"], "server_id": server_id})
        return public_server(fresh)
    mcp_store.update_server(
        user_id, server_id, status="needs_auth", last_error=None, sync_status="pending",
    )
    schedule_sync(user_id, server_id)
    fresh = mcp_store.get_server(user_id, server_id)
    return public_server(fresh)


def set_consent(user_id: int, server_id: int, granted: bool) -> dict:
    """D4：按服务器记录同意时间。撤回把时间清掉，之后不能再调用该服务的工具。"""
    row = mcp_store.get_server(user_id, server_id)
    if row is None:
        raise KeyError(server_id)
    if granted:
        stamp = db.now_iso()
        fresh = mcp_store.update_server(user_id, server_id, consent_at=stamp)
        db.audit(user_id, None, "mcp_consent_granted", {
            "server": row["slug"], "server_id": server_id, "consent_at": stamp,
        })
    else:
        fresh = mcp_store.update_server(user_id, server_id, consent_at=None)
        db.audit(user_id, None, "mcp_consent_revoked", {
            "server": row["slug"], "server_id": server_id,
        })
    return public_server(fresh)


def remove_server(user_id: int, server_id: int) -> bool:
    row = mcp_store.get_server(user_id, server_id)
    if row is None:
        return False
    drop_session((user_id, server_id))
    mcp_store.strip_slug_from_bots(user_id, row["slug"])
    ok = mcp_store.delete_server(user_id, server_id)
    if ok:
        db.audit(user_id, None, "mcp_server_removed", {"slug": row["slug"], "server_id": server_id})
    return ok


def connected_tool_rows(user_id: int) -> list[tuple[dict, dict]]:
    """已连接、熔断未打开、且用户已同意的工具。未同意的不放进模型能调用的列表。"""
    servers = {}
    for row in mcp_store.list_servers(user_id):
        if row["status"] != "connected":
            continue
        if not row.get("consent_at"):
            continue
        if circuit_state(row) == "open":
            continue
        servers[row["id"]] = row
    out = []
    for tool in mcp_store.list_tools(user_id):
        server = servers.get(tool["server_id"])
        if server and tool["status"] == "active":
            out.append((tool, server))
    return out


def invoke(user_id: int, server: dict, tool: dict, arguments: dict, call_id: str, bot_id: int | None = None) -> dict:
    """调用远程工具。每次调用都写审计，不保存外部原文。"""
    started = time.perf_counter()
    started_at = db.now_iso()
    slug = server["slug"]
    mcp_name = tool["mcp_name"]

    def finish(payload: dict, status: str, error_class: str | None) -> dict:
        _audit_call(
            user_id=user_id, bot_id=bot_id, server=slug, tool=mcp_name, call_id=call_id,
            arguments=arguments, status=status, error_class=error_class,
            started_at=started_at, duration_ms=_elapsed_ms(started),
        )
        return payload

    fresh = mcp_store.get_server(user_id, server["id"]) or server
    if not fresh.get("consent_at"):
        return finish(
            {"error": _CONSENT_MESSAGE, "code": "mcp_consent_required"},
            "error", "mcp_consent_required",
        )
    if circuit_state(fresh) == "open":
        return finish(
            {"error": _CIRCUIT_MESSAGE, "code": "mcp_circuit_open"},
            "error", "mcp_circuit_open",
        )
    spec = catalog.by_id(fresh.get("catalog_id") or "") or catalog.by_slug(fresh["slug"])
    url = (spec or {}).get("url") or fresh.get("url") or ""
    if not url:
        return finish(
            {"error": "尚未配置 MCP 服务地址", "code": "mcp_not_configured"},
            "error", "mcp_not_configured",
        )
    session = borrow_session((user_id, server["id"]), url, timeout_seconds())
    try:
        outcome = _call_with_retries(session, tool, arguments)
    except MCPTimeoutError as exc:
        _record_failure(user_id, server["id"])
        _remember_error(user_id, server["id"], exc)
        return finish({"error": exc.message, "code": exc.code}, "timeout", exc.code)
    except MCPSessionExpiredError as exc:
        _record_failure(user_id, server["id"])
        _remember_error(user_id, server["id"], exc)
        return finish({"error": exc.message, "code": exc.code}, "error", exc.code)
    except MCPRPCError:
        # 服务器按协议拒绝了。不是传输故障，不计入熔断，也不把对方原文写进审计。
        return finish(
            {"error": "MCP 服务拒绝了请求", "code": "mcp_rpc_error"},
            "error", "mcp_rpc_error",
        )
    except MCPClientError as exc:
        if _counts_toward_breaker(exc):
            _record_failure(user_id, server["id"])
            _remember_error(user_id, server["id"], exc)
        code = getattr(exc, "code", "mcp_unavailable")
        if code == "result_unknown":
            return finish({"error": _UNKNOWN_MESSAGE, "code": "result_unknown"}, "result_unknown", "result_unknown")
        return finish({"error": _safe_error(exc), "code": code}, "error", code)
    if outcome == "unknown":
        _record_failure(user_id, server["id"])
        return finish({"error": _UNKNOWN_MESSAGE, "code": "result_unknown"}, "result_unknown", "result_unknown")
    _record_success(user_id, server["id"])
    wrapped, truncated = wrap(slug, mcp_name, call_id, outcome.text)
    status = "error" if outcome.is_error else "ok"
    error_class = "mcp_tool_error" if outcome.is_error else None
    audited = finish(
        {
            "content": wrapped,
            "code": outcome.code,
            "is_error": outcome.is_error,
            "truncated": truncated,
            **({"error": wrapped} if outcome.is_error else {}),
        },
        status, error_class,
    )
    return audited


def _audit_call(*, user_id, bot_id, server, tool, call_id, arguments, status, error_class,
                started_at, duration_ms):
    """审计只留分类信息。不写工具返回的原文，也不写服务器响应体。"""
    db.audit(user_id, bot_id, "mcp_tool_call", {
        "server": server,
        "tool": tool,
        "call_id": call_id,
        "args_hash": hashlib.sha256(
            json.dumps(arguments, sort_keys=True, ensure_ascii=False, default=str).encode()
        ).hexdigest(),
        "status": status,
        "error_class": error_class,
        "duration_ms": duration_ms,
        "started_at": started_at,
        "finished_at": db.now_iso(),
    })


def _elapsed_ms(started: float) -> int:
    return int((time.perf_counter() - started) * 1000)


def _safe_error(exc: MCPClientError) -> str:
    """给界面和模型的固定说明，不带外部响应正文。"""
    code = getattr(exc, "code", "")
    if code == "mcp_timeout":
        return "MCP 服务超时"
    if code == "mcp_protocol":
        return "MCP 协议错误"
    if code == "mcp_session_expired":
        return "MCP 会话已失效"
    if code == "mcp_rpc_error":
        return "MCP 服务拒绝了请求"
    return "MCP 服务不可用"


def _counts_toward_breaker(exc: BaseException) -> bool:
    return isinstance(exc, (MCPTimeoutError, MCPUnavailableError, MCPSessionExpiredError))


def _idempotent(tool: dict) -> bool:
    """只读，或可信注解标明可重复。非幂等的传输失败不自动重试（设计稿 §8）。"""
    if tool.get("risk") == "read":
        return True
    ann = tool.get("annotations") or {}
    return bool(ann.get("idempotentHint"))


def _call_with_retries(session, tool: dict, arguments: dict):
    def op():
        return session.call_tool(tool["mcp_name"], arguments or {})

    try:
        return _with_retries(op, idempotent=_idempotent(tool))
    except _ResultUnknown:
        return "unknown"


class _ResultUnknown(Exception):
    pass


def _with_retries(op, *, idempotent: bool):
    """超时、5xx、连接错误才重试。工具 isError 与 4xx 由 op 正常返回或直接抛出，不进这里的重试。"""
    attempts = _retry_max() + 1
    last: MCPClientError | None = None
    for index in range(attempts):
        try:
            return op()
        except MCPSessionExpiredError:
            raise
        except MCPClientError as exc:
            if not isinstance(exc, (MCPTimeoutError, MCPUnavailableError)):
                raise
            last = exc
            can_retry = index + 1 < attempts
            if not can_retry:
                raise
            if not idempotent:
                raise _ResultUnknown() from exc
            _sleep_backoff(index, exc)
    if last:
        raise last
    raise MCPUnavailableError()


def _sleep_backoff(index: int, exc: MCPClientError):
    retry_after = getattr(exc, "retry_after", None)
    if isinstance(retry_after, (int, float)) and retry_after > 0:
        time.sleep(min(5.0, float(retry_after)))
        return
    backs = _backoffs()
    delay = backs[min(index, len(backs) - 1)]
    if delay > 0:
        delay += random.uniform(0, delay * 0.25)
        time.sleep(delay)


def _retry_max() -> int:
    raw = os.getenv("VERABOT_MCP_RETRY_MAX", str(MCP_RETRY_MAX_DEFAULT))
    try:
        return max(0, int(raw))
    except ValueError:
        return MCP_RETRY_MAX_DEFAULT


def _backoffs() -> list[float]:
    raw = os.getenv("VERABOT_MCP_RETRY_BACKOFF", MCP_RETRY_BACKOFF_DEFAULT)
    parts: list[float] = []
    for piece in raw.split(","):
        try:
            parts.append(max(0.0, float(piece.strip())))
        except ValueError:
            continue
    return parts or [0.5, 2.0]


def _breaker_threshold() -> int:
    raw = os.getenv("VERABOT_MCP_BREAKER_THRESHOLD", str(MCP_BREAKER_THRESHOLD_DEFAULT))
    try:
        return max(1, int(raw))
    except ValueError:
        return MCP_BREAKER_THRESHOLD_DEFAULT


def _breaker_cooldown() -> float:
    raw = os.getenv("VERABOT_MCP_BREAKER_COOLDOWN", str(MCP_BREAKER_COOLDOWN_DEFAULT))
    try:
        return max(0.0, float(raw))
    except ValueError:
        return float(MCP_BREAKER_COOLDOWN_DEFAULT)


def _record_success(user_id: int, server_id: int):
    row = mcp_store.get_server(user_id, server_id)
    if row is None:
        return
    if int(row.get("circuit_failures") or 0) or row.get("circuit_open_until"):
        mcp_store.update_server(user_id, server_id, circuit_failures=0, circuit_open_until=None)


def _record_failure(user_id: int, server_id: int):
    row = mcp_store.get_server(user_id, server_id)
    if row is None:
        return
    failures = int(row.get("circuit_failures") or 0) + 1
    if failures >= _breaker_threshold():
        until = (datetime.now(timezone.utc) + timedelta(seconds=_breaker_cooldown())).isoformat(timespec="microseconds")
        mcp_store.update_server(
            user_id, server_id, circuit_failures=failures, circuit_open_until=until,
            last_error=_CIRCUIT_MESSAGE,
        )
    else:
        mcp_store.update_server(user_id, server_id, circuit_failures=failures)


def _remember_error(user_id: int, server_id: int, exc: MCPClientError):
    mcp_store.update_server(user_id, server_id, last_error=_safe_error(exc))


def _empty_summary() -> dict:
    return {"added": [], "changed": [], "removed": [], "rejected": []}
