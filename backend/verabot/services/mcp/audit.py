"""MCP 工具调用审计：只记分类信息，不写外部原文。从 service.py 原样搬出。"""
from __future__ import annotations

import hashlib
import json
import time

from ... import db


def _audit_call(*, user_id, bot_id, server, tool, call_id, arguments, status, error_class,
                started_at, duration_ms, plugin_id=None):
    """审计只留分类信息。不写工具返回的原文，也不写服务器响应体。"""
    db.audit(user_id, bot_id, "mcp_tool_call", {
        "server": server,
        "tool": tool,
        "plugin_id": plugin_id,
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
