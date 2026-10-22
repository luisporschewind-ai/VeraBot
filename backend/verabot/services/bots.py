"""Bot 业务逻辑：公开字段、权限配置校验（含记忆授权）、新建默认能力、删除后的委派白名单清理。

新建 Bot 默认能力全开（2026-10-22 起）：全部内置工具 + 当前已连接且已同意服务的 active MCP 工具
（最多 `MCP_MAX_TOOLS_PER_BOT` 个），接受其他 Bot 委派，委派白名单包含账号内其他全部 Bot，记忆沿用
`bot_and_global`。显式传入 `allowed_tools` / `delegate_to` / `accept_delegation` 时以传入值为准。
"""
import json

from fastapi import HTTPException

from .. import db
from ..core.config import MCP_MAX_TOOLS_PER_BOT
from ..db import bot_store, mcp_store
from ..tools import REGISTRY
from .opening import generate as opening_generate
from .opening import address as opening_address

PUBLIC_FIELDS = ("id", "name", "avatar", "color", "appearance", "persona", "instructions", "created_at",
                 "allowed_tools", "delegate_to", "accept_delegation", "memory_access", "tags", "pinned_at")


def default_builtin_tools() -> list[str]:
    """默认开启的内置工具：注册表里全部 `kind == "builtin"` 的工具。

    记忆（`memory`）、图片 / 文件附件（`attachment`）和资料库（`library`）工具由各自的开关在调用时判定，
    不进 `allowed_tools`，所以这里排除。
    """
    return sorted(name for name, tool in REGISTRY.items() if tool.kind == "builtin")


def default_mcp_tools(user_id: int) -> list[str]:
    """默认开启的 MCP 工具：已连接、用户已同意该服务、工具状态为 active 的条目。

    只取创建 / 迁移这一时刻已经同步到本地的快照；之后新同步或新安装的工具仍需手动加入白名单
    （保留「新工具不自动授权」的防 rug-pull 规则）。按工具全名排序并截断到每 Bot 上限。
    """
    consented = {s["id"] for s in mcp_store.list_servers(user_id)
                 if s["status"] == "connected" and s.get("consent_at")}
    names = sorted({t["full_name"] for t in mcp_store.list_tools(user_id)
                    if t["server_id"] in consented and t["status"] == "active"})
    return names[:MCP_MAX_TOOLS_PER_BOT]


def default_tool_allowlist(user_id: int) -> list[str]:
    return sorted({*default_builtin_tools(), *default_mcp_tools(user_id)})


def default_delegate_targets(user_id: int, exclude_id: int | None = None) -> list[int]:
    """默认委派白名单：账号内其他全部 Bot（新建时「全开」，实际能否委派仍看对方接受委派与深度护栏）。"""
    return sorted(b["id"] for b in db.list_bots(user_id) if b["id"] != exclude_id)


def create_perms(user: dict, body) -> dict:
    """新建 Bot 的权限列：显式传入的字段沿用 `validate_perms`，未传入的字段使用「能力默认全开」。"""
    out = validate_perms(user, body, None)
    if body.allowed_tools is None:
        out["allowed_tools"] = json.dumps(default_tool_allowlist(user["id"]))
    if body.delegate_to is None:
        out["delegate_to"] = json.dumps(default_delegate_targets(user["id"]))
    if body.accept_delegation is None:
        out["accept_delegation"] = 1
    return out


def delegate_list_updates(user_id: int, bot_id: int) -> list[tuple[int, str]]:
    """新建 Bot 时要写回的 `(Bot id, delegate_to JSON)`：把它补进其他开启 `ask_bot` 的 Bot 的白名单。

    只追加新 Bot 的 id，不改动其他已有委派目标；关闭 `ask_bot` 的 Bot 不受影响。调用方在同一事务里写入。
    """
    updates = []
    for b in db.list_bots(user_id):
        if b["id"] == bot_id or "ask_bot" not in (b.get("allowed_tools") or []):
            continue
        current = b.get("delegate_to") or []
        if bot_id in current:
            continue
        updates.append((b["id"], json.dumps(sorted({*current, bot_id}))))
    return updates


def public_bot(b: dict, memory_count: int | None = None, *, include_opening_address: bool = True) -> dict:
    """memory_count：该 Bot 的生效「本 Bot 记忆」条数（不含全局资料）；None 时按需查询。"""
    out = {k: b[k] for k in PUBLIC_FIELDS}
    if memory_count is None:
        from . import memory
        memory_count = memory.bot_counts(b["user_id"]).get(b["id"], 0)
    out["memory_count"] = memory_count
    updated = b.get("image_updated_at")
    out["has_avatar"] = bool(updated)
    out["avatar_updated_at"] = updated
    out["opening_templates"] = opening_generate.load_stored(b)
    if include_opening_address:
        out["opening_address"] = opening_address.preferred_address(b["user_id"], b["id"])
    else:
        out["opening_address"] = None
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
                bot_store.set_delegate_to(c, b["id"], json.dumps([x for x in b["delegate_to"] if x != bot_id]))
