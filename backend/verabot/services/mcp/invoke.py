"""MCP 工具调用：同意 / 熔断 / 地址检查、带重试的远程调用、结果包装与审计。从 service.py 原样搬出。"""
from __future__ import annotations

import time

from ... import db
from ...db import mcp_store
from . import catalog
from .audit import _audit_call, _elapsed_ms
from . import auth as mcp_auth
from .http_client import (
    MCPAuthError,
    MCPClientError,
    MCPRPCError,
    MCPSessionExpiredError,
    MCPTimeoutError,
    borrow_session,
    timeout_seconds,
)
from .presenter import _plugin_id_of, circuit_state
from .resilience import (
    _CIRCUIT_MESSAGE,
    PluginUninstalled,
    _counts_toward_breaker,
    _idempotent,
    _interruptible,
    _record_failure,
    _record_success,
    _remember_error,
    _ResultUnknown,
    _safe_error,
    _server_alive,
    _with_retries,
)
from .sanitize import wrap

_CONSENT_MESSAGE = "尚未同意把这个 MCP 服务的工具结果发送给 DeepSeek，因此没有调用它。请在设置里同意后再试。"
_UNKNOWN_MESSAGE = "请求可能已执行，也可能没有。请到对应服务核实。"
_AUTH_MESSAGE = "这个服务需要重新连接（令牌无效、过期或已撤销）。请让用户在插件页更换令牌。"
_PERMISSION_MESSAGE = "服务拒绝了这次请求：令牌没有这个资源或这项权限。"
# fine-grained PAT 越权：HTTP 200 + isError，正文是 GitHub API 的 403 / 404 文本（计划 §5.3）
_PERMISSION_MARKERS = ("resource not accessible by personal access token", "403", "not found", "404")


def _permission_denied(text: str) -> bool:
    folded = (text or "").lower()
    return any(marker in folded for marker in _PERMISSION_MARKERS)


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
            plugin_id=_plugin_id_of(server),
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
    alive = lambda: _server_alive(user_id, server["id"])
    if not alive():
        return _uninstalled_result(finish, tool)
    provider = mcp_auth.provider_for(spec)
    headers = provider.headers(user_id, fresh)
    if headers is None or not provider.has_credential(user_id, fresh):
        return finish({"error": _AUTH_MESSAGE, "code": "mcp_auth_required"}, "error", "mcp_auth_required")
    timeout = float(spec["timeout"]) if spec and spec.get("timeout") else timeout_seconds()
    session = borrow_session((user_id, server["id"]), url, timeout, auth=headers)
    try:
        outcome = _call_with_retries(session, tool, arguments, alive=alive)
    except PluginUninstalled as exc:
        return _uninstalled_result(finish, tool, sent=exc.sent)
    except MCPAuthError as exc:
        # 运行中 401 / insufficient_scope：needs_auth，不重试、不计熔断，工具随即不进 schema
        from .sync import mark_auth_failed
        mark_auth_failed(user_id, server["id"], exc.auth_error, _plugin_id_of(fresh),
                         getattr(exc, "required_scopes", ()))
        return finish({"error": _AUTH_MESSAGE, "code": "mcp_auth_required"}, "error", "mcp_auth_required")
    except MCPTimeoutError as exc:
        if not alive():
            return _uninstalled_result(finish, tool, sent=True)
        _record_failure(user_id, server["id"])
        _remember_error(user_id, server["id"], exc)
        return finish({"error": exc.message, "code": exc.code}, "timeout", exc.code)
    except MCPSessionExpiredError as exc:
        if not alive():
            return _uninstalled_result(finish, tool, sent=True)
        _record_failure(user_id, server["id"])
        _remember_error(user_id, server["id"], exc)
        return finish({"error": exc.message, "code": exc.code}, "error", exc.code)
    except MCPRPCError:
        if not alive():
            return _uninstalled_result(finish, tool, sent=True)
        # 服务器按协议拒绝了。不是传输故障，不计入熔断，也不把对方原文写进审计。
        return finish(
            {"error": "MCP 服务拒绝了请求", "code": "mcp_rpc_error"},
            "error", "mcp_rpc_error",
        )
    except MCPClientError as exc:
        if not alive():
            return _uninstalled_result(finish, tool, sent=True)
        if _counts_toward_breaker(exc):
            _record_failure(user_id, server["id"])
            _remember_error(user_id, server["id"], exc)
        code = getattr(exc, "code", "mcp_unavailable")
        if code == "result_unknown":
            return finish({"error": _UNKNOWN_MESSAGE, "code": "result_unknown"}, "result_unknown", "result_unknown")
        return finish({"error": _safe_error(exc), "code": code}, "error", code)
    if not alive():
        return _uninstalled_result(finish, tool, sent=True)
    if outcome == "unknown":
        _record_failure(user_id, server["id"])
        return finish({"error": _UNKNOWN_MESSAGE, "code": "result_unknown"}, "result_unknown", "result_unknown")
    _record_success(user_id, server["id"])
    wrapped, truncated = wrap(slug, mcp_name, call_id, outcome.text)
    status = "error" if outcome.is_error else "ok"
    code = outcome.code
    if outcome.is_error and mcp_auth.requires_auth(spec) and _permission_denied(outcome.text):
        code = "mcp_permission_denied"   # 不计熔断；结果仍按不可信数据交给模型
    error_class = code if outcome.is_error else None
    audited = finish(
        {
            "content": wrapped,
            "code": code,
            "is_error": outcome.is_error,
            "truncated": truncated,
            **({"error": wrapped} if outcome.is_error else {}),
        },
        status, error_class,
    )
    return audited


def _uninstalled_result(finish, tool: dict, *, sent: bool = False) -> dict:
    """服务行已经没了。只读调用取消；非只读且请求已经发出时按 M2 返回 result_unknown。不计熔断。"""
    if sent and not _idempotent(tool):
        return finish(
            {"error": _UNKNOWN_MESSAGE, "code": "result_unknown"},
            "result_unknown", "result_unknown",
        )
    return finish(
        {"error": "插件已卸载，本次调用已取消", "code": "plugin_uninstalled"},
        "cancelled", "plugin_uninstalled",
    )


def _call_with_retries(session, tool: dict, arguments: dict, alive=None):
    def op():
        return _interruptible(lambda: session.call_tool(tool["mcp_name"], arguments or {}), alive)

    try:
        return _with_retries(op, idempotent=_idempotent(tool), alive=alive)
    except _ResultUnknown:
        return "unknown"
