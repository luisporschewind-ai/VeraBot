"""待确认操作（pending_actions）：MCP 写工具 HITL、后续 Gmail / 提醒共用。"""
from __future__ import annotations

import hashlib
import json
import os
from datetime import datetime, timedelta, timezone

from ... import db
from ...core import crypto
from ...core.config import ACTION_TTL_MIN_DEFAULT, MCP_PENDING_PER_TURN_DEFAULT
from ...db import action_store, mcp_store
from ..mcp import policy as mcp_policy
from ..mcp import service as mcp


KIND_MCP = "mcp_tool_call"


class ActionError(Exception):
    def __init__(self, status: int, message: str, code: str | None = None):
        super().__init__(message)
        self.status = status
        self.message = message
        self.code = code


def _ttl_minutes() -> int:
    raw = os.getenv("VERABOT_ACTION_TTL_MIN", str(ACTION_TTL_MIN_DEFAULT))
    try:
        return max(1, int(raw))
    except ValueError:
        return ACTION_TTL_MIN_DEFAULT


def pending_per_turn() -> int:
    raw = os.getenv("VERABOT_MCP_PENDING_PER_TURN", str(MCP_PENDING_PER_TURN_DEFAULT))
    try:
        return max(1, int(raw))
    except ValueError:
        return MCP_PENDING_PER_TURN_DEFAULT


def _expires_at(now: datetime | None = None) -> str:
    base = now or datetime.now(timezone.utc)
    return (base + timedelta(minutes=_ttl_minutes())).isoformat(timespec="seconds")


def _hash_payload(arguments: dict) -> str:
    blob = json.dumps(arguments, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(blob.encode()).hexdigest()


def _encrypt(arguments: dict) -> bytes:
    text = crypto.encrypt(json.dumps(arguments, ensure_ascii=False), "action")
    return text.encode()


def _decrypt(payload_enc) -> dict | None:
    if payload_enc is None:
        return None
    if isinstance(payload_enc, memoryview):
        payload_enc = payload_enc.tobytes()
    if isinstance(payload_enc, bytes):
        token = payload_enc.decode()
    else:
        token = str(payload_enc)
    plain = crypto.decrypt(token, "action")
    if plain is None:
        return None
    try:
        data = json.loads(plain)
    except ValueError:
        return None
    return data if isinstance(data, dict) else None


def create_mcp_pending(
    ctx,
    server: dict,
    tool: dict,
    arguments: dict,
    *,
    warnings: list[str] | None = None,
) -> dict:
    """冻结参数并写入 pending_actions；不调用远程。返回给模型的工具结果 + SSE 用字段。"""
    if getattr(ctx.turn, "pending_created", 0) >= pending_per_turn():
        db.audit(ctx.user_id, ctx.bot.get("id"), "tool_denied", {
            "tool": tool["full_name"], "reason": "pending_cap", "depth": ctx.depth,
        })
        return {
            "error": "本轮待确认操作已达上限，请先处理已有确认卡片",
            "code": "pending_cap",
        }
    payload_hash = _hash_payload(arguments)
    expires = _expires_at()
    action_id = action_store.insert(
        ctx.user_id,
        bot_id=ctx.bot.get("id"),
        kind=KIND_MCP,
        server_id=server["id"],
        tool_full_name=tool["full_name"],
        payload_enc=_encrypt(arguments),
        payload_hash=payload_hash,
        tool_def_hash=tool.get("def_hash") or tool.get("accepted_hash"),
        expires_at=expires,
    )
    ctx.turn.pending_created = getattr(ctx.turn, "pending_created", 0) + 1
    db.audit(ctx.user_id, ctx.bot.get("id"), "mcp_action_requested", {
        "action_id": action_id,
        "server": server.get("slug") or server.get("name"),
        "tool": tool.get("mcp_name") or tool.get("full_name"),
        "payload_hash": payload_hash,
        "risk": tool.get("risk"),
    })
    warn = list(warnings or [])
    label = tool.get("title") or tool.get("label") or tool.get("mcp_name") or tool["full_name"]
    return {
        "status": "pending_confirmation",
        "action_id": action_id,
        "message": "已请用户确认，尚未执行",
        "kind": KIND_MCP,
        "server": server.get("name") or server.get("slug"),
        "server_id": server["id"],
        "tool": tool["full_name"],
        "label": label,
        "arguments": arguments,
        "risk": tool.get("risk") or "destructive",
        "warnings": warn,
        "expires_at": expires,
        "payload_hash": payload_hash,
    }


def public_action(row: dict, *, include_args: bool = True) -> dict:
    """API / SSE 对外字段。不含密文。"""
    args = _decrypt(row.get("payload_enc")) if include_args else None
    server_name = None
    if row.get("server_id"):
        srv = mcp_store.get_server(row["user_id"], row["server_id"])
        if srv:
            server_name = srv.get("name") or srv.get("slug")
    tool_label = row.get("tool_full_name")
    risk = None
    if row.get("tool_full_name"):
        tool = mcp_store.get_tool_by_full_name(row["user_id"], row["tool_full_name"])
        if tool:
            tool_label = tool.get("title") or tool.get("mcp_name") or tool["full_name"]
            risk = tool.get("risk")
    out = {
        "id": row["id"],
        "kind": row["kind"],
        "status": row["status"],
        "bot_id": row.get("bot_id"),
        "server_id": row.get("server_id"),
        "server": server_name,
        "tool": row.get("tool_full_name"),
        "label": tool_label,
        "risk": risk,
        "result": row.get("result"),
        "created_at": row.get("created_at"),
        "expires_at": row.get("expires_at"),
        "decided_at": row.get("decided_at"),
    }
    if include_args and args is not None:
        out["arguments"] = args
    elif include_args:
        out["arguments"] = {}
        out["args_unavailable"] = True
    return out


def sse_payload(result: dict) -> dict:
    """从 create_mcp_pending 的返回值构造 confirmation_required 事件体。"""
    return {
        "action_id": result["action_id"],
        "kind": result.get("kind") or KIND_MCP,
        "server": result.get("server"),
        "server_id": result.get("server_id"),
        "tool": result.get("tool"),
        "label": result.get("label"),
        "arguments": result.get("arguments") or {},
        "risk": result.get("risk"),
        "warnings": result.get("warnings") or [],
        "expires_at": result.get("expires_at"),
    }


def _ensure_fresh(row: dict) -> dict:
    """pending 且已过期 → 标 expired 并抛 410。"""
    if row["status"] != "pending":
        return row
    now = db.now_iso()
    if row.get("expires_at") and row["expires_at"] <= now:
        expired = action_store.mark_expired(row["user_id"], row["id"], decided_at=now)
        db.audit(row["user_id"], row.get("bot_id"), "mcp_action_expired", {
            "action_id": row["id"],
            "server_id": row.get("server_id"),
            "tool": row.get("tool_full_name"),
        })
        raise ActionError(410, "确认已过期", "expired")
    return row


def list_actions(user_id: int, *, status: str | None = "pending", bot_id: int | None = None) -> list[dict]:
    rows = action_store.list_for_user(user_id, status=status, bot_id=bot_id)
    out = []
    for row in rows:
        if row["status"] == "pending" and row.get("expires_at") and row["expires_at"] <= db.now_iso():
            action_store.mark_expired(user_id, row["id"])
            db.audit(user_id, row.get("bot_id"), "mcp_action_expired", {
                "action_id": row["id"], "tool": row.get("tool_full_name"),
            })
            continue
        out.append(public_action(row))
    return out


def get_action(user_id: int, action_id: int) -> dict:
    row = action_store.get(user_id, action_id)
    if row is None:
        raise ActionError(404, "待确认操作不存在")
    try:
        _ensure_fresh(row)
    except ActionError:
        row = action_store.get(user_id, action_id) or row
        if row["status"] == "expired":
            raise
    return public_action(row)


def cancel(user_id: int, action_id: int) -> dict:
    row = action_store.get(user_id, action_id)
    if row is None:
        raise ActionError(404, "待确认操作不存在")
    _ensure_fresh(row)
    if row["status"] != "pending":
        raise ActionError(409, "该操作已经处理过", "already_decided")
    updated = action_store.decide(
        user_id, action_id, from_status="pending", to_status="cancelled", result="用户取消",
    )
    if updated is None:
        raise ActionError(409, "该操作已经处理过", "already_decided")
    db.audit(user_id, row.get("bot_id"), "mcp_action_cancelled", {
        "action_id": action_id,
        "server_id": row.get("server_id"),
        "tool": row.get("tool_full_name"),
    })
    return public_action(updated)


def confirm(user_id: int, action_id: int) -> dict:
    row = action_store.get(user_id, action_id)
    if row is None:
        raise ActionError(404, "待确认操作不存在")
    _ensure_fresh(row)
    if row["status"] != "pending":
        raise ActionError(409, "该操作已经处理过", "already_decided")
    if row["kind"] != KIND_MCP:
        raise ActionError(422, "暂不支持确认此类型的操作", "unsupported_kind")

    server = mcp_store.get_server(user_id, row["server_id"]) if row.get("server_id") else None
    if server is None or server.get("status") != "connected":
        raise ActionError(409, "MCP 服务未连接或已停用，无法执行", "not_connected")
    tool = mcp_store.get_tool_by_full_name(user_id, row["tool_full_name"] or "")
    if tool is None or tool.get("status") == "removed":
        raise ActionError(409, "工具已从服务中移除", "tool_removed")
    if tool.get("status") == "changed":
        raise ActionError(409, "工具定义已变更，请先在插件页接受变更", "tool_changed")
    expected = row.get("tool_def_hash")
    current = tool.get("def_hash") or tool.get("accepted_hash")
    if expected and current and expected != current:
        raise ActionError(409, "工具定义已变更，请先在插件页接受变更", "tool_changed")

    arguments = _decrypt(row.get("payload_enc"))
    if arguments is None:
        raise ActionError(500, "无法解密冻结参数（密钥缺失或已更换）", "payload_undecryptable")
    if _hash_payload(arguments) != row["payload_hash"]:
        raise ActionError(500, "参数校验失败", "payload_hash_mismatch")

    # 最终授权点：pending → 执行中与 TTL 检查处于同一 SQLite 写事务。
    claim_status, claimed = action_store.claim_for_execution(user_id, action_id)
    if claim_status == "expired":
        db.audit(user_id, row.get("bot_id"), "mcp_action_expired", {
            "action_id": action_id,
            "server_id": row.get("server_id"),
            "tool": row.get("tool_full_name"),
        })
        raise ActionError(410, "确认已过期", "expired")
    if claim_status == "missing":
        raise ActionError(404, "待确认操作不存在")
    if claim_status != "claimed":
        raise ActionError(409, "该操作已经处理过", "already_decided")
    row = claimed

    try:
        result = mcp.invoke(
            user_id, server, tool, arguments,
            call_id=f"pending_{action_id}", bot_id=row.get("bot_id"),
        )
    except Exception as exc:
        summary = f"执行异常：{type(exc).__name__}"
        with db.tx() as c:
            c.execute(
                "UPDATE pending_actions SET status=?, result=?, decided_at=? WHERE id=? AND user_id=?",
                ("failed", summary, db.now_iso(), action_id, user_id),
            )
        db.audit(user_id, row.get("bot_id"), "mcp_action_failed", {
            "action_id": action_id, "server": server.get("slug"),
            "tool": tool.get("mcp_name"), "error": type(exc).__name__,
        })
        raise ActionError(502, summary, "mcp_invoke_failed") from exc

    summary = _result_summary(result)
    final_status = _status_from_result(result)
    with db.tx() as c:
        c.execute(
            "UPDATE pending_actions SET status=?, result=?, decided_at=? WHERE id=? AND user_id=?",
            (final_status, summary, db.now_iso(), action_id, user_id),
        )
    db.audit(user_id, row.get("bot_id"), "mcp_action_confirmed" if final_status == "done" else "mcp_action_failed", {
        "action_id": action_id,
        "server": server.get("slug"),
        "tool": tool.get("mcp_name"),
        "payload_hash": row["payload_hash"],
        "status": final_status,
        "code": result.get("code"),
    })
    note = f"用户已确认并执行 {tool.get('title') or tool.get('mcp_name') or tool['full_name']}：{summary}"
    if row.get("bot_id"):
        db.add_message(user_id, row["bot_id"], "assistant", note, traces=None)
    fresh = action_store.get(user_id, action_id)
    out = public_action(fresh)
    out["execution"] = {
        "code": result.get("code"),
        "error": result.get("error"),
        "content_length": len(result.get("content") or ""),
        "truncated": bool(result.get("truncated")),
    }
    return out


def _status_from_result(result: dict) -> str:
    code = result.get("code")
    if code == "ok":
        return "done"
    if code == "result_unknown":
        return "unknown"
    return "failed"


def _result_summary(result: dict) -> str:
    if result.get("code") == "ok":
        n = len(result.get("content") or "")
        trunc = "，已截断" if result.get("truncated") else ""
        return f"已执行（约 {n} 字{trunc}）"
    if result.get("code") == "result_unknown":
        return result.get("error") or "结果未知，请到对应服务核实"
    return result.get("error") or f"失败：{result.get('code') or 'error'}"
