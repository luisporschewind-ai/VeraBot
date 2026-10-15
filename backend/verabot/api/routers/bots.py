"""Bot 管理（CRUD + 权限）与协作记录。"""
import json
import logging
import sqlite3

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException

from ... import db
from ...db import audit_store, bot_store, delegation_store, message_store
from ...core.config import MAX_BOTS_PER_USER
from ...services import memory
from ...services.memory import growth
from ...services.bots import public_bot, remove_from_delegate_lists, validate_perms
from ...services.attachments import repo as attachments
from ...services.opening import generate as opening_generate
from ..deps import current_user, require_bot
from ..schemas import BotIn, BotPatch

router = APIRouter(tags=["bots"])
log = logging.getLogger("verabot.bots")


async def _generate_opening_background(user_id: int, bot_id: int) -> None:
    bot = db.get_bot(user_id, bot_id)
    if bot is None or opening_generate.load_stored(bot) is not None:
        return
    templates = await opening_generate.generate_for_bot(
        bot.get("name") or "", bot.get("persona") or "", bot.get("instructions") or "",
    )
    if templates is not None:
        opening_generate.save_templates(user_id, bot_id, templates)
    else:
        log.info("opening templates unavailable for bot %s (client will fallback)", bot_id)


@router.get("/api/bots")
def bots_list(user=Depends(current_user)):
    out = []
    counts = memory.bot_counts(user["id"])
    with db.tx() as c:
        all_bots = db.list_bots(user["id"])
        pinned_bots = sorted((b for b in all_bots if b.get("pinned_at")),
                             key=lambda b: (b["pinned_at"], -b["id"]), reverse=True)
        unpinned_bots = sorted((b for b in all_bots if not b.get("pinned_at")), key=lambda b: b["id"])
        for b in pinned_bots + unpinned_bots:
            last = message_store.last_message(c, user["id"], b["id"])
            # 列表不解析称呼，避免 N 次记忆扫描
            out.append({**public_bot(b, counts.get(b["id"], 0), include_opening_address=False), "last_message": last})
    return {"bots": out, "limit": MAX_BOTS_PER_USER}


@router.post("/api/bots", status_code=201)
def bots_create(body: BotIn, background_tasks: BackgroundTasks, user=Depends(current_user)):
    perms = validate_perms(user, body, None)   # 未提供的权限字段使用列默认值 = 最小权限（Least privilege）
    with db.tx() as c:
        n = bot_store.count_for_user(c, user["id"])
        if n >= MAX_BOTS_PER_USER:   # 软上限（Soft limit），由 MAX_BOTS_PER_USER 配置
            raise HTTPException(400, f"已达到 Bot 数量上限（{MAX_BOTS_PER_USER} 个），可联系管理员调整")
        if bot_store.name_exists(c, user["id"], body.name):
            raise HTTPException(409, "已有同名 Bot")
        cols = {"user_id": user["id"], "name": body.name, "avatar": body.avatar or "🤖", "color": body.color,
                "persona": body.persona, "instructions": body.instructions,
                "tags": json.dumps(body.tags, ensure_ascii=False), "created_at": db.now_iso(), **perms}
        if body.appearance is not None:
            cols["appearance"] = json.dumps(body.appearance.model_dump(mode="json"), ensure_ascii=False, separators=(",", ":"))
        bid = bot_store.insert(c, cols)
    background_tasks.add_task(_generate_opening_background, user["id"], bid)
    return public_bot(db.get_bot(user["id"], bid))


@router.get("/api/bots/{bot_id}")
def bots_get(bot_id: int, user=Depends(current_user)):
    return public_bot(require_bot(user, bot_id))


@router.post("/api/bots/{bot_id}/opening-templates/ensure")
async def bots_ensure_opening(bot_id: int, user=Depends(current_user)):
    """存量 Bot 懒生成开场词模板；已有则原样返回。失败不写库，客户端用内置兜底。"""
    bot = require_bot(user, bot_id)
    result = await opening_generate.ensure_templates(user, bot)
    fresh = db.get_bot(user["id"], bot_id)
    return {
        **public_bot(fresh),
        "generated": result["generated"],
    }


@router.patch("/api/bots/{bot_id}")
def bots_patch(bot_id: int, body: BotPatch, background_tasks: BackgroundTasks, user=Depends(current_user)):
    require_bot(user, bot_id)
    pinned = body.pinned
    fields = {k: v for k, v in body.model_dump(exclude={"allowed_tools", "delegate_to", "accept_delegation", "memory_access", "pinned", "appearance"}).items()
              if v is not None}
    if "appearance" in body.model_fields_set:
        fields["appearance"] = (json.dumps(body.appearance.model_dump(mode="json"), ensure_ascii=False, separators=(",", ":"))
                                if body.appearance is not None else None)
    if "tags" in fields:
        fields["tags"] = json.dumps(fields["tags"], ensure_ascii=False)
    fields.update(validate_perms(user, body, bot_id))
    if pinned is False:
        fields["pinned_at"] = None
    pin_at = db.now_iso() if pinned is True else None   # 置顶：已置顶的保留原时间（COALESCE）
    # 名称/人设变更后清空模板，后台重新生成
    persona_changed = any(k in fields for k in ("name", "persona", "instructions"))
    if persona_changed:
        fields["opening_templates"] = None
    if fields or pin_at is not None:
        try:
            with db.tx() as c:
                bot_store.update_fields(c, user["id"], bot_id, fields, pin_at)
        except sqlite3.IntegrityError:   # BUG-03：只有唯一约束冲突才是 409
            raise HTTPException(409, "已有同名 Bot")
    if persona_changed:
        background_tasks.add_task(_generate_opening_background, user["id"], bot_id)
    return public_bot(db.get_bot(user["id"], bot_id))


@router.delete("/api/bots/{bot_id}")
def bots_delete(bot_id: int, user=Depends(current_user)):
    """删除 Bot：其 bot / summary 记忆随外键级联删除；它提议的全局记忆保留（source_bot_id 置 NULL）。"""
    require_bot(user, bot_id)
    att_keys = attachments.keys_for_bot(user["id"], bot_id)   # 图片行随 Bot 级联删除，文件在提交后删
    with db.tx() as c:
        bot_store.delete(c, user["id"], bot_id)
    attachments.delete_files(att_keys)
    remove_from_delegate_lists(user["id"], bot_id)   # 从其他 Bot 的委派白名单中移除该 id
    return {"ok": True}


@router.get("/api/bots/{bot_id}/delegations")
def bot_delegations(bot_id: int, limit: int = 50, user=Depends(current_user)):
    """协作记录（Delegation log）：该 Bot 发起或接收的委派，含共享载荷 / 回答 / token / 状态。"""
    require_bot(user, bot_id)
    with db.tx() as c:
        rs = delegation_store.list_for_bot(c, user["id"], bot_id, min(max(limit, 1), 200))
    return {"delegations": rs}


@router.get("/api/bots/{bot_id}/tool-calls")
def bot_tool_calls(bot_id: int, limit: int = 50, user=Depends(current_user)):
    """工具调用记录（MCP M3）：该 Bot 的 mcp_tool_call / mcp_action_* 审计，不含原文。"""
    require_bot(user, bot_id)
    kinds = (
        "mcp_tool_call", "mcp_action_requested", "mcp_action_confirmed",
        "mcp_action_cancelled", "mcp_action_expired", "mcp_action_failed",
    )
    lim = min(max(limit, 1), 200)
    with db.tx() as c:
        rows = audit_store.list_kinds(c, user["id"], bot_id, kinds, lim)
    out = []
    for r in rows:
        try:
            detail = json.loads(r["detail"] or "{}")
        except ValueError:
            detail = {}
        out.append({
            "id": r["id"],
            "kind": r["kind"],
            "created_at": r["created_at"],
            "server": detail.get("server") or detail.get("server_id"),
            "tool": detail.get("tool") or detail.get("full_name"),
            "status": detail.get("status") or detail.get("error_class"),
            "action_id": detail.get("action_id"),
            "duration_ms": detail.get("duration_ms"),
        })
    return {"tool_calls": out}


@router.get("/api/bots/{bot_id}/growth")
def bot_growth(bot_id:int,user=Depends(current_user)):
    result=growth.for_bot(user["id"],bot_id)
    if result is None: raise HTTPException(404,"Bot 不存在")
    return result
