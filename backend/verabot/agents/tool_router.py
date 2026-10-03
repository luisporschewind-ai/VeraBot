"""统一工具目录：内置工具走 registry，mcp__ 前缀走 MCP 客户端。"""
from __future__ import annotations

import asyncio
import json
import os

from .. import db
from ..core.config import MCP_CALLS_PER_TURN_DEFAULT
from ..db import delegation_store, mcp_store, plugin_store
from ..services.mcp import catalog as mcp_catalog
from ..services.mcp import service as mcp
from ..services.attachments.vision import guard_write as image_guard
from ..tools.registry import ToolContext, run_tool
from .permissions import get_schemas

_DENY = {
    "unknown_tool": "未知工具: {name}",
    "tool_not_allowed": "当前 Bot 未被授权使用该能力",
    "not_delegable": "被委派的 Bot 不能使用 MCP 工具",
    "not_connected": "MCP 服务未连接或已停用",
    "tool_changed": "MCP 工具定义已变更，需要先接受变更",
    "tool_removed": "MCP 工具已从服务中移除",
    "turn_cap": "本轮 MCP 调用次数已达上限",
    "needs_confirmation": "该操作需要确认后才能执行，当前版本暂不支持确认",
    "plugin_uninstalled": "插件已卸载，本次调用已取消",
}


def _calls_per_turn() -> int:
    raw = os.getenv("VERABOT_MCP_CALLS_PER_TURN", str(MCP_CALLS_PER_TURN_DEFAULT))
    try:
        return max(1, int(raw))
    except ValueError:
        return MCP_CALLS_PER_TURN_DEFAULT


def schemas_for(bot: dict, depth: int, memory_on: bool, user_id: int) -> list[dict]:
    """内置 schema，加上这个 Bot 白名单里、已连接且仍有效的 MCP 工具。委派深度 ≥ 1 时不暴露 MCP。"""
    tools = get_schemas(bot, depth, memory_on=memory_on)
    if depth >= 1:
        return tools
    allowed = set(bot.get("allowed_tools") or [])
    for tool, server in mcp.connected_tool_rows(user_id):
        if tool["full_name"] in allowed:
            tools.append(mcp.tool_schema(tool, server["name"]))
    return tools


def trace_meta(user_id: int, name: str) -> dict:
    if not name.startswith("mcp__"):
        return {"source": "builtin"}
    tool = mcp_store.get_tool_by_full_name(user_id, name)
    if tool is None:
        return {"source": "mcp"}
    server = mcp_store.get_server(user_id, tool["server_id"])
    return {"source": "mcp", "server": (server or {}).get("name"), "risk": tool.get("risk")}


async def dispatch(ctx: ToolContext, name: str, raw_args: str, call_id: str | None = None) -> dict:
    if name.startswith("mcp__"):
        return await asyncio.to_thread(_call_mcp, ctx, name, raw_args, call_id)
    denied = image_guard(ctx, name)   # 带图轮次：写工具需要用户确认（MCP 非只读工具本来就被拒绝）
    if denied:
        return denied
    return await run_tool(ctx, name, raw_args)


def _call_mcp(ctx: ToolContext, name: str, raw_args: str, call_id: str | None = None) -> dict:
    tool = mcp_store.get_tool_by_full_name(ctx.user_id, name)
    if tool is None:
        if _uninstalled_plugin(ctx.user_id, name):
            return _deny(ctx, name, "plugin_uninstalled")
        return _deny(ctx, name, "unknown_tool")
    if name not in (ctx.bot.get("allowed_tools") or []):
        return _deny(ctx, name, "tool_not_allowed")
    if ctx.depth >= 1:
        _delegation_rejected(ctx, name)
        return _deny(ctx, name, "not_delegable", audited=True)
    server = mcp_store.get_server(ctx.user_id, tool["server_id"])
    if server is None or server["status"] != "connected":
        return _deny(ctx, name, "not_connected")
    if tool["status"] == "changed":
        return _deny(ctx, name, "tool_changed")
    if tool["status"] == "removed":
        return _deny(ctx, name, "tool_removed")
    if ctx.turn.mcp_calls >= _calls_per_turn():
        return _deny(ctx, name, "turn_cap")
    if tool["risk"] != "read":
        return _deny(ctx, name, "needs_confirmation")
    try:
        args = json.loads(raw_args or "{}")
        if not isinstance(args, dict):
            raise ValueError("arguments must be an object")
    except Exception as exc:
        return {"error": f"参数解析失败: {exc}", "code": "mcp_invalid_arguments"}
    ctx.turn.mcp_calls += 1
    result = mcp.invoke(
        ctx.user_id, server, tool, args, call_id=call_id or name, bot_id=ctx.bot.get("id"),
    )
    if result.get("content") or result.get("code") == "mcp_tool_error":
        ctx.turn.untrusted_tainted = True
    return result


def _uninstalled_plugin(user_id: int, name: str) -> bool:
    """工具行已经没了，但这个 slug 属于用户卸下的插件时，用 plugin_uninstalled 而不是 unknown_tool。"""
    rest = name[len("mcp__"):]
    slug, sep, _tool = rest.partition("__")
    if not sep or not slug:
        return False
    spec = mcp_catalog.by_slug(slug)
    if spec is None:
        return False
    row = plugin_store.get(user_id, spec["catalog_id"])
    return row is not None and row["status"] == "uninstalled"


def _deny(ctx: ToolContext, name: str, reason: str, audited: bool = False) -> dict:
    if not audited:
        db.audit(ctx.user_id, ctx.bot.get("id"), "tool_denied",
                 {"tool": name, "reason": reason, "depth": ctx.depth})
    template = _DENY[reason]
    message = template.format(name=name) if "{name}" in template else template
    return {"error": message, "code": reason}


def _delegation_rejected(ctx: ToolContext, name: str):
    delegation_store.insert(user_id=ctx.user_id, from_bot_id=ctx.bot["id"], to_bot_id=0, question=name,
                            shared_context="", answer="", status="rejected", reason="not_delegable", depth=ctx.depth)
    db.audit(ctx.user_id, ctx.bot.get("id"), "tool_denied",
             {"tool": name, "reason": "not_delegable", "depth": ctx.depth})
