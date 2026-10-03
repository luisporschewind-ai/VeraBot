"""把目录、HTTP 客户端和数据库接在一起，给 API 与 Agent 用。"""
from __future__ import annotations

import hashlib
import json

from ... import db
from ...db import mcp_store
from . import catalog, sync
from .http_client import MCPClientError, MCPRPCError, MCPSession, MCPTimeoutError
from .naming import strip_extensions
from .sanitize import clean_description, wrap


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
    """补齐目录里的两个服务。默认开启的会同步一次；默认关闭的只建 disabled 行，不访问网络。"""
    for spec in catalog.entries():
        row = mcp_store.get_server_by_slug(user_id, spec["slug"])
        if row is None:
            status = "disabled" if not spec["enabled"] else "needs_auth"
            row = mcp_store.insert_server(user_id, spec, status)
            db.audit(user_id, None, "mcp_server_added", {
                "slug": spec["slug"], "source": "catalog", "catalog_id": spec["catalog_id"],
            })
            if spec["enabled"]:
                sync_server(user_id, row["id"])
        elif spec["enabled"] and row["status"] == "needs_auth" and not row.get("last_synced_at"):
            sync_server(user_id, row["id"])
    return [public_server(row) for row in mcp_store.list_servers(user_id)]


def sync_server(user_id: int, server_id: int) -> dict:
    row = mcp_store.get_server(user_id, server_id)
    if row is None:
        raise KeyError(server_id)
    spec = catalog.by_id(row.get("catalog_id") or "") or catalog.by_slug(row["slug"])
    url = (spec or {}).get("url") or row.get("url") or ""
    if not url:
        mcp_store.update_server(user_id, server_id, status="error", last_error="尚未配置 MCP 服务地址", url=None)
        fresh = mcp_store.get_server(user_id, server_id)
        return {**_empty_summary(), "server": public_server(fresh)}
    if row["status"] == "disabled":
        fresh = mcp_store.get_server(user_id, server_id)
        return {**_empty_summary(), "server": public_server(fresh)}
    try:
        with MCPSession(url) as session:
            tools = session.list_tools()
        summary = sync.apply(user_id, row, tools)
        fresh = mcp_store.update_server(
            user_id, server_id, status="connected", url=url, last_error=None, last_synced_at=db.now_iso(),
        )
    except MCPClientError as exc:
        fresh = mcp_store.update_server(user_id, server_id, status="error", url=url, last_error=exc.message)
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
    mcp_store.update_server(user_id, server_id, status="needs_auth", last_error=None)
    summary = sync_server(user_id, server_id)
    return summary["server"]


def remove_server(user_id: int, server_id: int) -> bool:
    row = mcp_store.get_server(user_id, server_id)
    if row is None:
        return False
    mcp_store.strip_slug_from_bots(user_id, row["slug"])
    ok = mcp_store.delete_server(user_id, server_id)
    if ok:
        db.audit(user_id, None, "mcp_server_removed", {"slug": row["slug"], "server_id": server_id})
    return ok


def connected_tool_rows(user_id: int) -> list[tuple[dict, dict]]:
    """已连接服务器上、状态为 active 的工具，连同服务器行。"""
    servers = {row["id"]: row for row in mcp_store.list_servers(user_id) if row["status"] == "connected"}
    out = []
    for tool in mcp_store.list_tools(user_id):
        server = servers.get(tool["server_id"])
        if server and tool["status"] == "active":
            out.append((tool, server))
    return out


def invoke(user_id: int, server: dict, tool: dict, arguments: dict, call_id: str) -> dict:
    """调用远程工具。isError 与 JSON-RPC error 用不同的 code 返回。"""
    spec = catalog.by_id(server.get("catalog_id") or "") or catalog.by_slug(server["slug"])
    url = (spec or {}).get("url") or server.get("url") or ""
    if not url:
        return {"error": "尚未配置 MCP 服务地址", "code": "mcp_not_configured"}
    try:
        with MCPSession(url) as session:
            outcome = session.call_tool(tool["mcp_name"], arguments)
    except MCPTimeoutError as exc:
        return {"error": exc.message, "code": exc.code}
    except MCPRPCError as exc:
        return {"error": f"MCP 服务拒绝了请求：{exc.message}", "code": "mcp_rpc_error"}
    except MCPClientError as exc:
        return {"error": exc.message, "code": exc.code}
    wrapped, truncated = wrap(server["slug"], tool["mcp_name"], call_id, outcome.text)
    db.audit(user_id, None, "mcp_tool_call", {
        "server": server["slug"],
        "tool": tool["mcp_name"],
        "args_hash": hashlib.sha256(json.dumps(arguments, sort_keys=True, ensure_ascii=False).encode()).hexdigest(),
        "args_summary": json.dumps(arguments, ensure_ascii=False)[:64],
        "status": "error" if outcome.is_error else "ok",
        "result_chars": len(outcome.text),
    })
    if outcome.is_error:
        return {
            "error": wrapped,
            "code": "mcp_tool_error",
            "is_error": True,
            "content": wrapped,
            "truncated": truncated,
        }
    return {"content": wrapped, "code": "ok", "is_error": False, "truncated": truncated}


def _empty_summary() -> dict:
    return {"added": [], "changed": [], "removed": [], "rejected": []}
