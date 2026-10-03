"""用量、工具列表、健康检查。"""
from fastapi import APIRouter, Depends

from ...core.config import (DEEPSEEK_MODEL, MAX_BOTS_PER_USER, MAX_DELEGATION_DEPTH, MAX_DELEGATIONS_PER_TURN,
                            MAX_SHARED_CONTEXT, MEMORY_INJECT_MAX, MEMORY_MAX_ACTIVE)
from ...services import memory
from ...services.quota import compute_quota
from ...services.mcp import service as mcp_service
from ...tools import REGISTRY
from ..deps import current_user

router = APIRouter(tags=["meta"])


@router.get("/api/quota")
def quota(user=Depends(current_user)):
    return compute_quota(user)


@router.get("/api/tools")
def tools_list(user=Depends(current_user)):
    labels = {"get_weather": "天气查询", "create_reminder": "创建提醒", "list_reminders": "查看提醒", "ask_bot": "委派其他 Bot"}
    builtin_plugin = {
        "get_weather": "builtin_weather",
        "create_reminder": "builtin_reminder",
        "list_reminders": "builtin_reminder",
    }
    tools = [{"name": t.name, "label": labels.get(t.name, t.name), "description": t.description,
              "delegation": t.delegation, "source": "builtin", "server": None, "server_id": None,
              "risk": None, "requires_confirmation": False, "delegable": not t.delegation, "status": "active",
              "plugin_id": builtin_plugin.get(t.name)}
             for t in REGISTRY.values() if t.kind != "memory"]
    for tool, server in mcp_service.connected_tool_rows(user["id"]):
        tools.append({**mcp_service.public_tool(tool), "name": tool["full_name"],
                      "delegation": False, "source": "mcp", "server": server["name"],
                      "plugin_id": server.get("plugin_id") or server.get("catalog_id")})
    return {"tools": tools,
            # 记忆工具不在工具白名单里（由 Bot 的 memory_access 控制），这里只给摘要信息；旧客户端忽略该字段
            "memory": {"enabled": memory.enabled_for(user["id"]), "max_active": MEMORY_MAX_ACTIVE,
                       "inject_max": MEMORY_INJECT_MAX},
            "guardrails": {"max_delegation_depth": MAX_DELEGATION_DEPTH, "max_delegations_per_turn": MAX_DELEGATIONS_PER_TURN,
                           "max_shared_context": MAX_SHARED_CONTEXT, "max_bots_per_user": MAX_BOTS_PER_USER}}


@router.get("/api/health")
def health():
    return {"ok": True, "model": DEEPSEEK_MODEL}
