"""安装 / 卸载 / 启用 / 同意 / 同步。派生 state 只在这里计算。"""
from __future__ import annotations

from ... import db
from ...core.config import plugin_default_installed
from ...db import mcp_store, plugin_store
from ..mcp import catalog as mcp_catalog
from ..mcp import service as mcp
from ..mcp.http_client import drop_session
from . import catalog


class PluginError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


_STATE_ORDER = (
    "not_installed",
    "disabled",
    "circuit_open",
    "syncing",
    "error",
    "needs_consent",
    "ready",
)


def _rank(state: str) -> int:
    try:
        return _STATE_ORDER.index(state)
    except ValueError:
        return len(_STATE_ORDER)


def _server_state(row: dict) -> str:
    if row["status"] == "disabled":
        return "disabled"
    if mcp.circuit_state(row) == "open":
        return "circuit_open"
    sync = row.get("sync_status") or "pending"
    if sync in ("pending", "syncing"):
        return "syncing"
    if sync == "error" or row["status"] == "error":
        return "error"
    if not row.get("consent_at"):
        return "needs_consent"
    return "ready"


def _servers(user_id: int, plugin_id: str) -> list[dict]:
    out = []
    for row in mcp_store.list_servers(user_id):
        pid = row.get("plugin_id") or row.get("catalog_id")
        if pid == plugin_id:
            out.append(row)
    return out


def _blank_runtime() -> dict:
    return {
        "enabled": False,
        "state": "not_installed",
        "consent_at": None,
        "tools_count": 0,
        "sync_status": None,
        "last_synced_at": None,
        "last_error": None,
        "circuit_state": "closed",
        "circuit_open_until": None,
        "consecutive_failures": 0,
        "servers": [],
    }


def _runtime(user_id: int, spec: dict, installed: bool) -> dict:
    if spec["kind"] == "builtin":
        return {
            "enabled": True,
            "state": "ready",
            "consent_at": None,
            "tools_count": len(spec.get("tools") or []),
            "sync_status": None,
            "last_synced_at": None,
            "last_error": None,
            "circuit_state": "closed",
            "circuit_open_until": None,
            "consecutive_failures": 0,
            "servers": [],
        }
    if not installed:
        blank = _blank_runtime()
        return blank
    rows = _servers(user_id, spec["plugin_id"])
    if not rows:
        runtime = _blank_runtime()
        runtime["state"] = "syncing"
        runtime["enabled"] = True
        runtime["sync_status"] = "pending"
        return runtime
    ranked = sorted(rows, key=lambda row: _rank(_server_state(row)))
    worst = ranked[0]
    state = _server_state(worst)
    consent_at = None
    if all(row.get("consent_at") for row in rows):
        consent_at = max(row["consent_at"] for row in rows)
    return {
        "enabled": all(row["status"] != "disabled" for row in rows),
        "state": state,
        "consent_at": consent_at,
        "tools_count": sum(mcp_store.tool_count(user_id, row["id"]) for row in rows),
        "sync_status": worst.get("sync_status") or "pending",
        "last_synced_at": worst.get("last_synced_at"),
        "last_error": worst.get("last_error"),
        "circuit_state": mcp.circuit_state(worst),
        "circuit_open_until": worst.get("circuit_open_until"),
        "consecutive_failures": int(worst.get("circuit_failures") or 0),
        "servers": [mcp.public_server(row) for row in rows],
    }


def public_plugin(user_id: int, spec: dict, installed: bool | None = None) -> dict:
    if installed is None:
        if spec["kind"] == "builtin":
            installed = True
        else:
            installed = spec["plugin_id"] in plugin_store.installed_ids(user_id)
    runtime = _runtime(user_id, spec, bool(installed))
    available = True
    if spec["kind"] == "mcp":
        mcp_spec = mcp_catalog.by_id(spec["catalog_id"] or "")
        available = bool(mcp_spec and mcp_spec.get("url"))
    return {
        "plugin_id": spec["plugin_id"],
        "kind": spec["kind"],
        "name": spec["name"],
        "description": spec["description"],
        "category": spec.get("category") or "",
        "publisher": spec["publisher"],
        "version": spec["version"],
        "icon": spec["icon"],
        "auth_mode": spec["auth_mode"],
        "trust": spec["trust"],
        "installed": bool(installed),
        "available": available,
        "removable": bool(spec["removable"]),
        "enabled": runtime["enabled"],
        "state": runtime["state"],
        "consent_required": bool(spec["consent_required"]),
        "consent_at": runtime["consent_at"],
        "data_notice": spec["data_notice"],
        "tools_count": runtime["tools_count"],
        "sync_status": runtime["sync_status"],
        "last_synced_at": runtime["last_synced_at"],
        "last_error": runtime["last_error"],
        "circuit_state": runtime["circuit_state"],
        "circuit_open_until": runtime["circuit_open_until"],
        "consecutive_failures": runtime["consecutive_failures"],
        "servers": runtime["servers"],
    }


def list_installed(user_id: int) -> list[dict]:
    backfill_installed(user_id)
    installed = plugin_store.installed_ids(user_id)
    out = [public_plugin(user_id, spec, True) for spec in catalog.builtins()]
    for spec in catalog.mcp_plugins():
        if spec["plugin_id"] in installed:
            out.append(public_plugin(user_id, spec, True))
    return out


def list_catalog(user_id: int) -> list[dict]:
    installed = plugin_store.installed_ids(user_id)
    return [public_plugin(user_id, spec, spec["plugin_id"] in installed) for spec in catalog.mcp_plugins()]


def get_plugin(user_id: int, plugin_id: str) -> dict:
    spec = catalog.by_id(plugin_id)
    if spec is None:
        raise PluginError(404, "未知插件")
    if spec["kind"] == "builtin":
        return public_plugin(user_id, spec, True)
    if plugin_id not in plugin_store.installed_ids(user_id):
        raise PluginError(404, "还没有安装这个插件")
    backfill_installed(user_id)
    return public_plugin(user_id, spec, True)


def _require_mcp(plugin_id: str) -> dict:
    spec = catalog.by_id(plugin_id)
    if spec is None:
        raise PluginError(404, "未知插件")
    if spec["kind"] == "builtin":
        raise PluginError(422, "内置插件不能这样操作")
    return spec


def _require_installed(user_id: int, plugin_id: str) -> dict:
    spec = _require_mcp(plugin_id)
    if plugin_id not in plugin_store.installed_ids(user_id):
        raise PluginError(404, "还没有安装这个插件")
    return spec


def _ensure_server_row(user_id: int, spec: dict, mcp_spec: dict, *, enable: bool) -> dict:
    row = mcp_store.get_server_by_slug(user_id, mcp_spec["slug"])
    if row is None:
        row = mcp_store.insert_server(user_id, mcp_spec, "needs_auth")
        db.audit(user_id, None, "mcp_server_added", {
            "slug": mcp_spec["slug"], "source": "catalog", "catalog_id": mcp_spec["catalog_id"],
            "plugin_id": spec["plugin_id"],
        })
        return row
    fields = {"plugin_id": spec["plugin_id"]}
    if enable and row["status"] == "disabled":
        fields["status"] = "needs_auth"
        fields["sync_status"] = "pending"
        fields["last_error"] = None
    elif enable and (row.get("sync_status") or "pending") not in ("ok", "syncing"):
        fields["sync_status"] = "pending"
        fields["last_error"] = None
        if row["status"] in ("disabled", "error"):
            fields["status"] = "needs_auth"
    return mcp_store.update_server(user_id, row["id"], **fields)


def install(user_id: int, plugin_id: str) -> dict:
    spec = catalog.by_id(plugin_id)
    if spec is None:
        raise PluginError(404, "未知插件")
    if spec["kind"] == "builtin":
        raise PluginError(422, "内置插件不需要安装")
    if spec["auth_mode"] != "none":
        raise PluginError(422, "当前版本不支持需要授权的插件")
    mcp_spec = mcp_catalog.by_id(spec["catalog_id"] or "")
    if mcp_spec is None or not mcp_spec.get("url"):
        raise PluginError(422, "尚未配置插件服务地址")
    if plugin_store.mark_installed(user_id, plugin_id, spec["version"]) == "exists":
        raise PluginError(409, "已经安装过这个插件")
    row = _ensure_server_row(user_id, spec, mcp_spec, enable=True)
    mcp.maybe_schedule(user_id, row)
    db.audit(user_id, None, "plugin_installed", {
        "plugin_id": plugin_id, "catalog_version": spec["version"],
    })
    return public_plugin(user_id, spec, True)


def uninstall(user_id: int, plugin_id: str) -> dict:
    spec = catalog.by_id(plugin_id)
    if spec is None:
        raise PluginError(404, "未知插件")
    if spec["kind"] == "builtin" or not spec["removable"]:
        raise PluginError(422, "内置插件不能卸载")
    result = plugin_store.commit_uninstall(user_id, plugin_id)
    if result is None:
        raise PluginError(404, "还没有安装这个插件")
    for server_id in result["server_ids"]:
        drop_session((user_id, server_id))
    for slug, server_id in zip(result["slugs"], result["server_ids"]):
        db.audit(user_id, None, "mcp_server_removed", {
            "slug": slug, "server_id": server_id, "plugin_id": plugin_id,
        })
    db.audit(user_id, None, "plugin_uninstalled", {
        "plugin_id": plugin_id, "catalog_version": spec["version"],
    })
    return {
        "ok": True,
        "removed_tools": result["removed_tools"],
        "affected_bots": result["affected_bots"],
    }


def set_enabled(user_id: int, plugin_id: str, enabled: bool) -> dict:
    spec = _require_installed(user_id, plugin_id)
    rows = _servers(user_id, plugin_id)
    if not rows:
        raise PluginError(404, "还没有安装这个插件")
    for row in rows:
        mcp.set_enabled(user_id, row["id"], enabled)
    return public_plugin(user_id, spec, True)


def set_consent(user_id: int, plugin_id: str, granted: bool) -> dict:
    spec = catalog.by_id(plugin_id)
    if spec is None:
        raise PluginError(404, "未知插件")
    if spec["kind"] == "builtin":
        raise PluginError(422, "内置插件不需要同意")
    if plugin_id not in plugin_store.installed_ids(user_id):
        raise PluginError(404, "还没有安装这个插件")
    rows = _servers(user_id, plugin_id)
    if not rows:
        raise PluginError(404, "还没有安装这个插件")
    for row in rows:
        mcp.set_consent(user_id, row["id"], granted)
    return public_plugin(user_id, spec, True)


def list_tools(user_id: int, plugin_id: str) -> list[dict]:
    spec = catalog.by_id(plugin_id)
    if spec is None:
        raise PluginError(404, "未知插件")
    if spec["kind"] == "builtin":
        raise PluginError(404, "内置插件的工具在 Bot 的工具权限里")
    if plugin_id not in plugin_store.installed_ids(user_id):
        raise PluginError(404, "还没有安装这个插件")
    out = []
    for row in _servers(user_id, plugin_id):
        out.extend(mcp.public_tool(tool) for tool in mcp_store.list_tools(user_id, row["id"]))
    return out


def sync(user_id: int, plugin_id: str) -> dict:
    spec = _require_installed(user_id, plugin_id)
    rows = _servers(user_id, plugin_id)
    if not rows:
        raise PluginError(404, "还没有安装这个插件")
    if all(row["status"] == "disabled" for row in rows):
        raise PluginError(409, "插件已停用，先启用再刷新工具")
    added: list[str] = []
    changed: list[str] = []
    removed: list[str] = []
    for row in rows:
        if row["status"] == "disabled":
            continue
        summary = mcp.sync_server(user_id, row["id"])
        added.extend(summary.get("added") or [])
        changed.extend(summary.get("changed") or [])
        removed.extend(summary.get("removed") or [])
    return {
        "added": added,
        "changed": changed,
        "removed": removed,
        "plugin": public_plugin(user_id, spec, True),
    }


def backfill_installed(user_id: int) -> None:
    """只为已安装插件补 mcp_servers 行。新用户没有任何记录时，按 default_installed 自动安装（当前为空）。

    墓碑（status=uninstalled）不会被补回来。不在这个函数里访问网络。
    """
    if not plugin_store.has_any(user_id):
        for plugin_id in sorted(plugin_default_installed()):
            spec = catalog.by_id(plugin_id)
            if spec is None or spec["kind"] != "mcp":
                continue
            try:
                install(user_id, plugin_id)
            except PluginError:
                continue
    for plugin_id in plugin_store.installed_ids(user_id):
        spec = catalog.by_id(plugin_id)
        if spec is None or spec["kind"] != "mcp":
            continue
        mcp_spec = mcp_catalog.by_id(spec["catalog_id"] or "")
        if mcp_spec is None:
            continue
        row = mcp_store.get_server_by_slug(user_id, mcp_spec["slug"])
        if row is None:
            row = mcp_store.insert_server(user_id, mcp_spec, "needs_auth")
            db.audit(user_id, None, "mcp_server_added", {
                "slug": mcp_spec["slug"], "source": "catalog", "catalog_id": mcp_spec["catalog_id"],
                "plugin_id": plugin_id,
            })
        elif row.get("plugin_id") != plugin_id:
            row = mcp_store.update_server(user_id, row["id"], plugin_id=plugin_id)
        mcp.maybe_schedule(user_id, row)


def visible_servers(user_id: int) -> list[dict]:
    backfill_installed(user_id)
    installed = plugin_store.installed_ids(user_id)
    out = []
    for row in mcp_store.list_servers(user_id):
        pid = row.get("plugin_id") or row.get("catalog_id")
        if pid in installed:
            out.append(mcp.public_server(row))
    return out
