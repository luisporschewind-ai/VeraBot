"""MCP 对外展示 / 序列化：目录、服务、工具、给模型的 function schema、熔断状态。从 service.py 原样搬出。"""
from __future__ import annotations

from datetime import datetime, timezone

from ...db import mcp_store
from . import catalog
from .naming import strip_extensions
from .sanitize import clean_description


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
    server = mcp_store.get_server(row["user_id"], row["server_id"])
    plugin_id = None
    if server:
        plugin_id = server.get("plugin_id") or server.get("catalog_id")
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
        "plugin_id": plugin_id,
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


def _plugin_id_of(row: dict) -> str | None:
    return row.get("plugin_id") or row.get("catalog_id")


def _empty_summary() -> dict:
    return {"added": [], "changed": [], "removed": [], "rejected": []}
