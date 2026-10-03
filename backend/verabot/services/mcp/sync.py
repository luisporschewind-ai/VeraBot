"""tools/list → mcp_tools。新工具不进入任何 Bot 的白名单。"""
from __future__ import annotations

import hashlib
import json
import os

from ... import db
from ...core.config import MCP_MAX_TOOLS_PER_SERVER_DEFAULT
from ...db import mcp_store
from . import catalog
from .naming import header_rejected, namespace


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
    taken = {t["full_name"] for t in mcp_store.list_tools(user_id)}
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
