"""Bot 管理（CRUD + 权限）与协作记录。"""
import json
import sqlite3

from fastapi import APIRouter, Depends, HTTPException

from ... import db
from ...core.config import MAX_BOTS_PER_USER
from ...services import memory
from ...services.bots import public_bot, remove_from_delegate_lists, validate_perms
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
            last = db.row(c.execute("SELECT content, created_at FROM messages WHERE user_id=? AND bot_id=? "
                                    "ORDER BY id DESC LIMIT 1", (user["id"], b["id"])).fetchone())
            out.append({**public_bot(b, counts.get(b["id"], 0)), "last_message": last})
    return {"bots": out, "limit": MAX_BOTS_PER_USER}


@router.post("/api/bots", status_code=201)
def bots_create(body: BotIn, user=Depends(current_user)):
    perms = validate_perms(user, body, None)   # 未提供的权限字段使用列默认值 = 最小权限（Least privilege）
    with db.tx() as c:
        n = c.execute("SELECT COUNT(*) FROM bots WHERE user_id=?", (user["id"],)).fetchone()[0]
        if n >= MAX_BOTS_PER_USER:   # 软上限（Soft limit），由 MAX_BOTS_PER_USER 配置
            raise HTTPException(400, f"已达到 Bot 数量上限（{MAX_BOTS_PER_USER} 个），可联系管理员调整")
        if c.execute("SELECT 1 FROM bots WHERE user_id=? AND name=?", (user["id"], body.name)).fetchone():
            raise HTTPException(409, "已有同名 Bot")
        cols = {"user_id": user["id"], "name": body.name, "avatar": body.avatar or "🤖", "color": body.color,
                "persona": body.persona, "instructions": body.instructions,
                "tags": json.dumps(body.tags, ensure_ascii=False), "created_at": db.now_iso(), **perms}
        bid = c.execute(f"INSERT INTO bots({','.join(cols)}) VALUES ({','.join('?' * len(cols))})",
                        tuple(cols.values())).lastrowid
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
    if pinned is True:
        sets = [f"{k}=?" for k in fields]
        sets.append("pinned_at=COALESCE(pinned_at, ?)")
        values = [*fields.values(), db.now_iso(), bot_id, user["id"]]
    else:
        sets = [f"{k}=?" for k in fields]
        values = [*fields.values(), bot_id, user["id"]]
    if sets:
        try:
            with db.tx() as c:
                c.execute(f"UPDATE bots SET {','.join(sets)} WHERE id=? AND user_id=?", values)
        except sqlite3.IntegrityError:   # BUG-03：只有唯一约束冲突才是 409
            raise HTTPException(409, "已有同名 Bot")
    return public_bot(db.get_bot(user["id"], bot_id))


@router.delete("/api/bots/{bot_id}")
def bots_delete(bot_id: int, user=Depends(current_user)):
    """删除 Bot：其 bot / summary 记忆随外键级联删除；它提议的全局记忆保留（source_bot_id 置 NULL）。"""
    require_bot(user, bot_id)
    with db.tx() as c:
        c.execute("DELETE FROM bots WHERE id=? AND user_id=?", (bot_id, user["id"]))
    remove_from_delegate_lists(user["id"], bot_id)   # 从其他 Bot 的委派白名单中移除该 id
    return {"ok": True}


@router.get("/api/bots/{bot_id}/delegations")
def bot_delegations(bot_id: int, limit: int = 50, user=Depends(current_user)):
    """协作记录（Delegation log）：该 Bot 发起或接收的委派，含共享载荷 / 回答 / token / 状态。"""
    require_bot(user, bot_id)
    with db.tx() as c:
        rs = db.rows(c.execute(
            "SELECT d.id, d.from_bot_id, fb.name AS from_bot, fb.avatar AS from_avatar, d.to_bot_id, tb.name AS to_bot, "
            "tb.avatar AS to_avatar, d.question, d.shared_context, d.shared_truncated, d.payload, d.answer, d.status, "
            "d.reason, d.depth, d.prompt_tokens, d.completion_tokens, d.total_tokens, d.created_at "
            "FROM delegations d LEFT JOIN bots fb ON fb.id=d.from_bot_id LEFT JOIN bots tb ON tb.id=d.to_bot_id "
            "WHERE d.user_id=? AND (d.from_bot_id=? OR d.to_bot_id=?) ORDER BY d.id DESC LIMIT ?",
            (user["id"], bot_id, bot_id, min(max(limit, 1), 200))).fetchall())
    return {"delegations": rs}
