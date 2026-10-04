"""安装 / 卸载 / 启用 / 同意 / 同步。派生 state 只在这里计算。"""
from __future__ import annotations

import logging
import os
from datetime import datetime, timezone

import httpx

from ... import db
from ...core import crypto
from ...core.config import plugin_default_installed
from ...db import mcp_store, plugin_store
from ..mcp import auth as mcp_auth
from ..mcp import catalog as mcp_catalog
from ..mcp import service as mcp
from ..mcp.http_client import (MCPAuthError, MCPClientError, MCPSession, MCPTimeoutError, MCPUnavailableError,
                               drop_session)
from ..mcp.sync import apply as apply_tools
from ..mcp.sync import server_timeout
from . import catalog

log = logging.getLogger("verabot.plugins")


class PluginError(Exception):
    def __init__(self, status: int, message: str, code: str | None = None):
        super().__init__(message)
        self.status = status
        self.message = message
        self.code = code


_STATE_ORDER = (
    "not_installed",
    "disabled",
    "needs_auth",
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
    spec = mcp_auth.spec_for(row)
    if mcp_auth.requires_auth(spec) and not mcp_auth.provider_for(spec).has_credential(row["user_id"], row):
        return "needs_auth"
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
    mcp_spec = None
    if spec["kind"] == "mcp":
        mcp_spec = mcp_catalog.by_id(spec["catalog_id"] or "")
        available = bool(mcp_spec and mcp_spec.get("url"))   # 需授权插件：地址已配置即可，不要求已连接
    account = _account(user_id, spec, mcp_spec, bool(installed))
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
        # v13 需授权连接器（全部可选，旧客户端忽略）。令牌本身永远不出现在响应里。
        "auth_connected": account["auth_connected"],
        "account_label": account["account_label"],
        "credential_hint": account["credential_hint"],
        "credential_expires_at": account["credential_expires_at"],
        "auth_error": account["auth_error"],
        "credential_help": account["credential_help"],
        "credential_help_url": account["credential_help_url"],
        "tools_changed": account["tools_changed"],
    }


def _account(user_id: int, spec: dict, mcp_spec: dict | None, installed: bool) -> dict:
    out = {"auth_connected": None, "account_label": None, "credential_hint": None, "credential_expires_at": None,
           "auth_error": None, "credential_help": None, "credential_help_url": None, "tools_changed": []}
    if spec["kind"] != "mcp":
        return out
    rows = _servers(user_id, spec["plugin_id"]) if installed else []
    out["tools_changed"] = [t["mcp_name"] for row in rows for t in mcp_store.list_tools(user_id, row["id"])
                            if t["status"] == "changed"]
    if not mcp_auth.requires_auth(mcp_spec):
        return out
    cred_spec = (mcp_spec or {}).get("credential") or {}
    out["credential_help"] = cred_spec.get("help")
    out["credential_help_url"] = cred_spec.get("help_url")
    out["auth_connected"] = False
    for row in rows:
        out["auth_error"] = row.get("auth_error")
        out["account_label"] = row.get("account_label")
        cred = mcp_store.get_credential(user_id, row["id"])
        if cred:
            out["credential_hint"] = cred.get("token_hint")
            out["credential_expires_at"] = cred.get("expires_at")
        out["auth_connected"] = mcp_auth.provider_for(mcp_spec).has_credential(user_id, row)
    return out


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
    if spec["auth_mode"] not in ("none", "bearer"):
        raise PluginError(422, "当前版本不支持这种授权方式")   # oauth：P2
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


# ---------------- 连接器凭据（v13，static_bearer） ----------------
def allow_lan_credentials() -> bool:
    return os.getenv("VERABOT_ALLOW_LAN_CREDENTIALS", "0").strip().lower() in ("1", "true", "yes", "on")


def _bearer_target(user_id: int, plugin_id: str) -> tuple[dict, dict, dict]:
    spec = _require_installed(user_id, plugin_id)
    mcp_spec = mcp_catalog.by_id(spec["catalog_id"] or "")
    if mcp_spec is None or mcp_spec.get("auth") != "bearer":
        raise PluginError(422, "这个插件不需要令牌", "credential_not_supported")
    rows = _servers(user_id, plugin_id)
    if not rows:
        raise PluginError(404, "还没有安装这个插件")
    return spec, mcp_spec, rows[0]


def _verify(mcp_spec: dict, token: str) -> list[dict]:
    """用新令牌 initialize + tools/list 一次（不重试）。令牌只在这个临时会话里。"""
    with MCPSession(mcp_spec["url"], timeout=server_timeout(mcp_spec),
                    headers=mcp_auth.bearer_headers(mcp_spec, token), auth_version="verify") as session:
        return session.list_tools()


def _probe_account(mcp_spec: dict, token: str) -> tuple[str | None, str | None]:
    """可选：取账号名与令牌到期时间（GitHub REST GET /user）。失败不影响连接。"""
    probe = mcp_spec.get("account_probe")
    if not probe:
        return None, None
    try:
        resp = httpx.get(probe["url"], headers={"Authorization": f"Bearer {token}", "Accept": "application/json",
                                                "User-Agent": "VeraBot/0.1.0"},
                         timeout=10.0, follow_redirects=False)
    except httpx.HTTPError:
        return None, None
    if resp.status_code != 200:
        return None, None
    label = None
    try:
        value = resp.json().get(probe.get("field") or "login")
        label = str(value)[:100] if value else None
    except ValueError:
        pass
    expires = None
    raw = resp.headers.get(probe.get("expiry_header") or "", "").strip()
    if raw:   # 例：2026-11-03 12:00:00 UTC
        try:
            parsed = datetime.strptime(raw.replace(" UTC", "").strip(), "%Y-%m-%d %H:%M:%S")
            expires = parsed.replace(tzinfo=timezone.utc).isoformat()
        except ValueError:
            expires = None
    return label, expires


def set_credential(user_id: int, plugin_id: str, token: str, *, secure_transport: bool) -> dict:
    spec, mcp_spec, row = _bearer_target(user_id, plugin_id)
    if not secure_transport and not allow_lan_credentials():
        raise PluginError(403, "令牌只能经本机（127.0.0.1）或 HTTPS 上传。请在调试页把服务器地址改为 127.0.0.1 后重试。",
                          "insecure_transport")
    token = (token or "").strip()
    if not mcp_auth.format_ok(mcp_spec, token):
        raise PluginError(422, "令牌格式不对，请检查是否完整复制", "credential_format")
    try:
        tools = _verify(mcp_spec, token)
    except MCPAuthError:
        db.audit(user_id, None, "mcp_auth_failed", {"plugin_id": plugin_id, "reason": "credential_invalid"})
        raise PluginError(422, "令牌无效、已过期或没有权限，未保存", "credential_invalid") from None
    except (MCPTimeoutError, MCPUnavailableError):
        raise PluginError(502, "网络不可达，令牌未保存。请确认 Mac 的代理已开启", "network_unreachable") from None
    except MCPClientError:
        raise PluginError(422, "服务拒绝了这个令牌，未保存", "credential_invalid") from None
    label, expires = _probe_account(mcp_spec, token)
    token_hint = mcp_auth.hint(token)
    mcp_store.upsert_credential(
        user_id, row["id"], kind="static_bearer", issuer=f"static:{mcp_spec['catalog_id']}",
        access_token_enc=crypto.encrypt(token, "token"), token_hint=token_hint, expires_at=expires,
    )
    del token
    drop_session((user_id, row["id"]))
    fields = {"auth_error": None, "last_error": None, "auth_type": "bearer"}
    if label:
        fields["account_label"] = label
    row = mcp_store.update_server(user_id, row["id"], **fields)
    db.audit(user_id, None, "mcp_credential_set", {
        "plugin_id": plugin_id, "kind": "static_bearer", "token_hint": token_hint, "account_label": label,
    })
    if row["status"] != "disabled":
        # 校验时已拿到 tools/list：直接写入并置 connected（与后台同步同一 apply）
        apply_tools(user_id, row, tools)
        mcp_store.update_server_unless_disabled(
            user_id, row["id"], status="connected", sync_status="ok", last_synced_at=db.now_iso(),
            circuit_failures=0, circuit_open_until=None,
        )
    return public_plugin(user_id, spec, True)


def delete_credential(user_id: int, plugin_id: str) -> dict:
    """断开：删凭据、清会话，回到 needs_auth；保留同意时间与 Bot 白名单。"""
    spec, _mcp_spec, row = _bearer_target(user_id, plugin_id)
    if not mcp_store.delete_credential(user_id, row["id"]):
        raise PluginError(404, "还没有连接", "credential_missing")
    drop_session((user_id, row["id"]))
    mcp_store.update_server_unless_disabled(
        user_id, row["id"], status="needs_auth", sync_status="pending", auth_error=None, last_error=None,
    )
    mcp_store.update_server(user_id, row["id"], account_label=None)
    db.audit(user_id, None, "mcp_credential_removed", {"plugin_id": plugin_id, "kind": "static_bearer"})
    return public_plugin(user_id, spec, True)


def accept_tool_changes(user_id: int, plugin_id: str) -> dict:
    """D7：一键接受这个插件所有「定义已变化」的工具（列出名字，完整差异审阅以后做）。"""
    spec = _require_installed(user_id, plugin_id)
    accepted = []
    for row in _servers(user_id, plugin_id):
        for tool in mcp_store.list_tools(user_id, row["id"]):
            if tool["status"] == "changed" and mcp_store.accept_change(user_id, tool["id"]):
                accepted.append(tool["mcp_name"])
                db.audit(user_id, None, "mcp_tool_change_accepted",
                         {"tool_id": tool["id"], "full_name": tool["full_name"], "plugin_id": plugin_id})
    return {"accepted": accepted, "plugin": public_plugin(user_id, spec, True)}


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
