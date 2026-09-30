"""用量、工具列表、健康检查。"""
from fastapi import APIRouter, Depends

from ...core.config import (DEEPSEEK_MODEL, MAX_BOTS_PER_USER, MAX_DELEGATION_DEPTH, MAX_DELEGATIONS_PER_TURN,
                            MAX_SHARED_CONTEXT)
from ...services.quota import compute_quota
from ...tools import REGISTRY
from ..deps import current_user

router = APIRouter(tags=["meta"])


@router.get("/api/quota")
def quota(user=Depends(current_user)):
    return compute_quota(user)


@router.get("/api/tools")
def tools_list(user=Depends(current_user)):
    labels = {"get_weather": "天气查询", "create_reminder": "创建提醒", "list_reminders": "查看提醒", "ask_bot": "委派其他 Bot"}
    return {"tools": [{"name": t.name, "label": labels.get(t.name, t.name), "description": t.description,
                       "delegation": t.delegation} for t in REGISTRY.values()],
            "guardrails": {"max_delegation_depth": MAX_DELEGATION_DEPTH, "max_delegations_per_turn": MAX_DELEGATIONS_PER_TURN,
                           "max_shared_context": MAX_SHARED_CONTEXT, "max_bots_per_user": MAX_BOTS_PER_USER}}


@router.get("/api/health")
def health():
    return {"ok": True, "model": DEEPSEEK_MODEL}
