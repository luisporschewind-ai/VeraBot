"""tools/list → mcp_tools。新工具不进入任何 Bot 的白名单。

后半部分是后台同步调度（schedule_sync / sync_server），从 service.py 原样搬入；service.py 仍 re-export。
"""
from __future__ import annotations

import hashlib
import json
import logging
import os
import sqlite3
import threading

from ... import db
from ...core.config import MCP_MAX_TOOLS_PER_SERVER_DEFAULT
from ...db import mcp_store
from . import catalog
from .http_client import MCPClientError, borrow_session, timeout_seconds
from .naming import header_rejected, namespace
from .presenter import _empty_summary, circuit_state, public_server
from .resilience import (
    _CIRCUIT_MESSAGE,
    PluginUninstalled,
    _counts_toward_breaker,
    _record_failure,
    _record_success,
    _safe_error,
    _server_alive,
    _with_retries,
)

log = logging.getLogger("verabot.mcp")

# 后台同步：同一 (user, server) 同时只跑一个。显式 POST /sync 会排队再跑一遍。
_INFLIGHT: set[tuple[int, int]] = set()
_INFLIGHT_LOCK = threading.Lock()
_SERVER_LOCKS: dict[tuple[int, int], threading.Lock] = {}


def _max_tools() -> int:
    raw = os.getenv("VERABOT_MCP_MAX_TOOLS_PER_SERVER", str(MCP_MAX_TOOLS_PER_SERVER_DEFAULT))
    try:
        return max(1, int(raw))
    except ValueError:
        return MCP_MAX_TOOLS_PER_SERVER_DEFAULT


def definition_hash(description: str, input_schema, output_schema, annotations) -> str:
    payload = json.dumps(
        {
            "description": description or "",
            "input_schema": input_schema,
            "output_schema": output_schema,
            "annotations": annotations,
        },
        sort_keys=True, ensure_ascii=False, separators=(",", ":"),
    )
    return hashlib.sha256(payload.encode()).hexdigest()


def risk_for(catalog_id: str | None, mcp_name: str, annotations: dict | None) -> str:
    """有效风险。目录里点名的只读工具，在注解没有明确否认时记为 read。"""
    ann = annotations or {}
    read_only = ann.get("readOnlyHint")
    known = catalog.READ_ONLY_TOOLS.get(catalog_id or "", frozenset())
    if mcp_name in known and read_only is not False:
        return "read"
    if read_only is True:
        return "read"
    destructive = ann.get("destructiveHint")
    level = "write" if destructive is False else "destructive"
    open_world = ann.get("openWorldHint")
    if open_world is not False and read_only is not True and _rank(level) < _rank("send"):
        level = "send"
    if _heuristic(mcp_name) == "destructive":
        level = "destructive"
    elif _heuristic(mcp_name) == "send" and _rank(level) < _rank("send"):
        level = "send"
    return level


def _rank(level: str) -> int:
    return {"read": 0, "write": 1, "send": 2, "destructive": 3}.get(level, 3)


def _heuristic(name: str) -> str | None:
    folded = name.lower()
    if any(word in folded for word in ("delete", "remove", "trash", "purge", "revoke")):
        return "destructive"
    if any(word in folded for word in ("send", "reply", "forward", "post", "publish", "share", "invite", "transfer", "pay")):
        return "send"
    return None


def _reject_reason(tool: dict) -> str | None:
    name = tool.get("name")
    if not isinstance(name, str):
        return "name"
    schema = tool.get("inputSchema") if "inputSchema" in tool else tool.get("input_schema")
    if schema is None:
        schema = {"type": "object", "properties": {}}
    if not isinstance(schema, dict) or schema.get("type") not in (None, "object"):
        return "schema"
    if header_rejected(schema):
        return "x-mcp-header"
    if namespace("learn", name, set()) is None and not _name_ok(name):
        return "name"
    return None


def _name_ok(name: str) -> bool:
    from .naming import MCP_NAME
    return bool(MCP_NAME.fullmatch(name))


def apply(user_id: int, server: dict, tools: list[dict]) -> dict:
    """把一次 tools/list 写入 mcp_tools。返回 added / changed / removed / rejected。"""
    added, changed, rejected = [], [], []
    seen: set[str] = set()
    # 本服务已有的名字不算占用。否则每次重新同步都会把自己的工具当成冲突，改掉 full_name。
    taken = {
        t["full_name"]
        for t in mcp_store.list_tools(user_id)
        if t["server_id"] != server["id"]
    }
    limit = _max_tools()
    kept = 0
    for tool in tools:
        reason = _reject_reason(tool)
        mcp_name = tool.get("name") if isinstance(tool.get("name"), str) else ""
        if reason:
            rejected.append({"name": mcp_name or "?", "reason": reason})
            db.audit(user_id, None, "mcp_tool_rejected", {"server_id": server["id"], "name": mcp_name, "reason": reason})
            continue
        if kept >= limit:
            rejected.append({"name": mcp_name, "reason": "limit"})
            continue
        full = namespace(server["slug"], mcp_name, taken)
        if full is None:
            rejected.append({"name": mcp_name, "reason": "name"})
            db.audit(user_id, None, "mcp_tool_rejected", {"server_id": server["id"], "name": mcp_name, "reason": "name"})
            continue
        taken.add(full)
        seen.add(mcp_name)
        kept += 1
        annotations = tool.get("annotations") if isinstance(tool.get("annotations"), dict) else None
        schema = tool.get("inputSchema") if isinstance(tool.get("inputSchema"), dict) else {"type": "object", "properties": {}}
        output = tool.get("outputSchema") if isinstance(tool.get("outputSchema"), dict) else None
        description = str(tool.get("description") or "")
        outcome = mcp_store.upsert_tool(user_id, server["id"], {
            "mcp_name": mcp_name,
            "full_name": full,
            "title": tool.get("title"),
            "description": description,
            "input_schema": schema,
            "output_schema": output,
            "annotations": annotations,
            "def_hash": definition_hash(description, schema, output, annotations),
            "risk": risk_for(server.get("catalog_id"), mcp_name, annotations),
        })
        if outcome == "added":
            added.append(full)
        elif outcome == "changed":
            changed.append(full)
    removed = mcp_store.mark_removed(server["id"], seen)
    db.audit(user_id, None, "mcp_tools_synced", {
        "server_id": server["id"], "slug": server["slug"],
        "added": added, "changed": changed, "removed": removed,
        "rejected": [item["name"] for item in rejected],
    })
    return {"added": added, "changed": changed, "removed": removed, "rejected": rejected}


# ---------------- 后台同步调度（从 service.py 搬入） ----------------
def maybe_schedule(user_id: int, row: dict) -> None:
    spec = catalog.by_id(row.get("catalog_id") or "") or catalog.by_slug(row["slug"])
    if _should_schedule(row, spec):
        schedule_sync(user_id, row["id"])


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
        except KeyError:
            log.debug("mcp background sync stopped, server gone user=%s server=%s", user_id, server_id)
        except sqlite3.IntegrityError:
            log.debug("mcp background sync stopped, plugin uninstalled user=%s server=%s", user_id, server_id)
        except Exception:
            if mcp_store.get_server(user_id, server_id) is None:
                log.debug("mcp background sync stopped, server gone user=%s server=%s", user_id, server_id)
            else:
                log.exception("mcp background sync failed user=%s server=%s", user_id, server_id)
                try:
                    mcp_store.update_server(
                        user_id, server_id, status="error", sync_status="error", last_error="同步失败",
                    )
                except sqlite3.IntegrityError:
                    log.debug("mcp background sync could not record failure, server gone")
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
    if not _server_alive(user_id, server_id):
        return _empty_summary()
    mcp_store.update_server(user_id, server_id, sync_status="syncing", url=url)
    try:
        session = borrow_session((user_id, server_id), url, timeout_seconds())
        if not _server_alive(user_id, server_id):
            return _empty_summary()
        tools = _with_retries(
            session.list_tools, idempotent=True,
            alive=lambda: _server_alive(user_id, server_id),
        )
        if not _server_alive(user_id, server_id):
            return _empty_summary()
        summary = apply(user_id, row, tools)
        if not _server_alive(user_id, server_id):
            return _empty_summary()
        _record_success(user_id, server_id)
        current = mcp_store.get_server(user_id, server_id) or row
        fields = {"url": url, "last_error": None, "last_synced_at": db.now_iso(), "sync_status": "ok"}
        # 同步过程中用户可能已经停用。停用优先，不要被这次结果改回已连接。
        if current.get("status") != "disabled":
            fields["status"] = "connected"
        fresh = mcp_store.update_server(user_id, server_id, **fields)
        if fresh is None:
            return _empty_summary()
    except PluginUninstalled:
        log.debug("mcp sync aborted, plugin uninstalled user=%s server=%s", user_id, server_id)
        return _empty_summary()
    except sqlite3.IntegrityError:
        log.debug("mcp sync aborted, plugin uninstalled user=%s server=%s", user_id, server_id)
        return _empty_summary()
    except MCPClientError as exc:
        if not _server_alive(user_id, server_id):
            log.debug("mcp sync aborted, plugin uninstalled user=%s server=%s", user_id, server_id)
            return _empty_summary()
        current = mcp_store.get_server(user_id, server_id)
        if current and current["status"] == "disabled":
            return {**_empty_summary(), "server": public_server(current)}
        if _counts_toward_breaker(exc):
            _record_failure(user_id, server_id)
        fresh = mcp_store.update_server(
            user_id, server_id, status="error", url=url, sync_status="error",
            last_error=_safe_error(exc),
        )
        summary = _empty_summary()
    return {**summary, "server": public_server(fresh)}
