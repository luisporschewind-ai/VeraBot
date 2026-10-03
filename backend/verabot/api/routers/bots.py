"""Bot 管理（CRUD + 权限）与协作记录。"""
import json
import sqlite3

from fastapi import APIRouter, Depends, HTTPException

from ... import db
from ...db import bot_store, delegation_store, message_store
from ...core.config import MAX_BOTS_PER_USER
from ...services import memory
from ...services.bots import public_bot, remove_from_delegate_lists, validate_perms
from ...services.attachments import repo as attachments
from ..deps import current_user, require_bot
from ..schemas import BotIn, BotPatch

router = APIRouter(tags=["bots"])


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
            out.append({**public_bot(b, counts.get(b["id"], 0)), "last_message": last})
    return {"bots": out, "limit": MAX_BOTS_PER_USER}


@router.post("/api/bots", status_code=201)
def bots_create(body: BotIn, user=Depends(current_user)):
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
        bid = bot_store.insert(c, cols)
    return public_bot(db.get_bot(user["id"], bid))


@router.get("/api/bots/{bot_id}")
def bots_get(bot_id: int, user=Depends(current_user)):
    return public_bot(require_bot(user, bot_id))


@router.patch("/api/bots/{bot_id}")
def bots_patch(bot_id: int, body: BotPatch, user=Depends(current_user)):
    require_bot(user, bot_id)
    pinned = body.pinned
    fields = {k: v for k, v in body.model_dump(exclude={"allowed_tools", "delegate_to", "accept_delegation", "memory_access", "pinned"}).items()
              if v is not None}
    if "tags" in fields:
        fields["tags"] = json.dumps(fields["tags"], ensure_ascii=False)
    fields.update(validate_perms(user, body, bot_id))
    if pinned is False:
        fields["pinned_at"] = None
    pin_at = db.now_iso() if pinned is True else None   # 置顶：已置顶的保留原时间（COALESCE）
    if fields or pin_at is not None:
        try:
            with db.tx() as c:
                bot_store.update_fields(c, user["id"], bot_id, fields, pin_at)
        except sqlite3.IntegrityError:   # BUG-03：只有唯一约束冲突才是 409
            raise HTTPException(409, "已有同名 Bot")
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
