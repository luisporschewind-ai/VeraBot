"""把目录、HTTP 客户端和数据库接在一起，给 API 与 Agent 用。

门面（facade）：这里只留服务管理（ensure / 启停 / 同意 / 删除 / 已连接工具），其余实现按职责拆到
presenter（展示 / 序列化）、sync（后台同步调度）、invoke（工具调用）、resilience（重试 + 熔断）、
audit（调用审计），并在这里 re-export，调用方写法不变。
"""
from __future__ import annotations

import logging

from ... import db
from ...db import mcp_store, plugin_store
from .http_client import drop_session
from .invoke import invoke  # noqa: F401
from .presenter import (  # noqa: F401
    _plugin_id_of,
    circuit_state,
    public_catalog,
    public_server,
    public_tool,
    tool_schema,
)
from .resilience import PluginUninstalled  # noqa: F401
from .sync import maybe_schedule, schedule_sync, sync_server  # noqa: F401

log = logging.getLogger("verabot.mcp")


def ensure_servers(user_id: int) -> list[dict]:
    """只返回已安装插件的服务。不在这个请求里访问网络，也不再把未安装的目录条目补回来。"""
    from ..plugins.service import visible_servers
    return visible_servers(user_id)


def set_enabled(user_id: int, server_id: int, enabled: bool) -> dict:
    row = mcp_store.get_server(user_id, server_id)
    if row is None:
        raise KeyError(server_id)
    if not enabled:
        fresh = mcp_store.update_server(user_id, server_id, status="disabled")
        db.audit(user_id, None, "mcp_server_disabled", {
            "slug": row["slug"], "server_id": server_id, "plugin_id": _plugin_id_of(row),
        })
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
            "plugin_id": _plugin_id_of(row),
        })
    else:
        fresh = mcp_store.update_server(user_id, server_id, consent_at=None)
        db.audit(user_id, None, "mcp_consent_revoked", {
            "server": row["slug"], "server_id": server_id, "plugin_id": _plugin_id_of(row),
        })
    return public_server(fresh)


def remove_server(user_id: int, server_id: int) -> bool:
    row = mcp_store.get_server(user_id, server_id)
    if row is None:
        return False
    from . import auth as mcp_auth
    spec = mcp_auth.spec_for(row)
    if spec and spec.get("auth") == "oauth":
        from .oauth import disconnect as disconnect_oauth
        disconnect_oauth(user_id, row, spec)
    drop_session((user_id, server_id))
    mcp_store.strip_slug_from_bots(user_id, row["slug"])
    ok = mcp_store.delete_server(user_id, server_id)
    if ok:
        plugin_id = _plugin_id_of(row)
        db.audit(user_id, None, "mcp_server_removed", {
            "slug": row["slug"], "server_id": server_id, "plugin_id": plugin_id,
        })
        if plugin_id:
            plugin_store.tombstone(user_id, plugin_id)
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
