"""Bot 业务逻辑：公开字段、权限配置校验（含记忆授权）、删除后的委派白名单清理。"""
import json

from fastapi import HTTPException

from .. import db
from ..core.config import MCP_MAX_TOOLS_PER_BOT
from ..db import mcp_store
from ..tools import REGISTRY

PUBLIC_FIELDS = ("id", "name", "avatar", "color", "persona", "instructions", "created_at",
                 "allowed_tools", "delegate_to", "accept_delegation", "memory_access", "tags", "pinned_at")


def public_bot(b: dict, memory_count: int | None = None) -> dict:
    """memory_count：该 Bot 的生效「本 Bot 记忆」条数（不含全局资料）；None 时按需查询。"""
    out = {k: b[k] for k in PUBLIC_FIELDS}
    if memory_count is None:
        from . import memory
        memory_count = memory.bot_counts(b["user_id"]).get(b["id"], 0)
    out["memory_count"] = memory_count
    updated = b.get("image_updated_at")
    out["has_avatar"] = bool(updated)
    out["avatar_updated_at"] = updated
    return out


def validate_perms(user: dict, body, self_id: int | None) -> dict:
    """服务端校验权限配置：工具必须存在；委派目标必须是本人的其他 Bot。返回需写入的列。"""
    out = {}
    if body.allowed_tools is not None:
        mcp_names = []
        for name in body.allowed_tools:
            if name.startswith("mcp__"):
                tool = mcp_store.get_tool_by_full_name(user["id"], name)
                if tool is None or tool["status"] != "active":
                    raise HTTPException(422, f"未知工具：{name}")
                mcp_names.append(name)
                continue
            if name not in REGISTRY:
                raise HTTPException(422, f"未知工具：{name}")
            if REGISTRY[name].kind == "memory":
                raise HTTPException(422, "记忆能力在「记忆」设置中管理，不能放进工具白名单")
        if len(set(mcp_names)) > MCP_MAX_TOOLS_PER_BOT:
            raise HTTPException(422, f"每个 Bot 最多开启 {MCP_MAX_TOOLS_PER_BOT} 个 MCP 工具")
        out["allowed_tools"] = json.dumps(sorted(set(body.allowed_tools)))
    if body.delegate_to is not None:
        mine = {b["id"] for b in db.list_bots(user["id"])}
        ids = sorted(set(body.delegate_to))
        if self_id in ids:
            raise HTTPException(422, "不能把自己设为委派目标")
        if any(i not in mine for i in ids):
            raise HTTPException(422, "委派目标必须是你自己的其他 Bot")
        out["delegate_to"] = json.dumps(ids)
    if body.accept_delegation is not None:
        out["accept_delegation"] = int(body.accept_delegation)
    if getattr(body, "memory_access", None) is not None:
        out["memory_access"] = body.memory_access
    return out


def remove_from_delegate_lists(user_id: int, bot_id: int):
    """从其他 Bot 的委派白名单中移除该 id（删除 Bot 后调用）。"""
    for b in db.list_bots(user_id):
        if bot_id in b["delegate_to"]:
            with db.tx() as c:
                c.execute("UPDATE bots SET delegate_to=? WHERE id=?",
                          (json.dumps([x for x in b["delegate_to"] if x != bot_id]), b["id"]))
