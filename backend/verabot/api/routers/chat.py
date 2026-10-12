"""消息历史与流式对话（SSE）。"""
import json

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import StreamingResponse

from ... import db
from ...db import message_store
from ...agents.runtime import run_chat
from ...services import memory
from ...services.memory import jobs as memory_jobs
from ...services.attachments import repo as attachments
from ..deps import current_user, require_bot
from ..schemas import ChatIn

router = APIRouter(tags=["chat"])


@router.get("/api/bots/{bot_id}/messages/sync")
def messages_sync(bot_id: int, limit: int = Query(default=100, ge=1, le=100),
                  before_id: int | None = Query(default=None, gt=0),
                  expected_revision: int | None = Query(default=None, ge=0), user=Depends(current_user)):
    """Revision-pinned history page used for local snapshot reconciliation."""
    require_bot(user, bot_id)
    with db.tx() as c:
        row = c.execute("SELECT revision FROM conversation_revisions WHERE user_id=? AND kind='private' AND conversation_id=?",
                        (user["id"], bot_id)).fetchone()
        revision = int(row[0]) if row else 0
        if expected_revision is not None and expected_revision != revision:
            raise HTTPException(409, {"code": "sync_revision_changed", "message": "对话正在更新，请重新同步"})
        if before_id is None and expected_revision == revision:
            return {"revision": revision, "messages": [], "next_before_id": None, "unchanged": True}
        cursor = before_id if before_id is not None else 9223372036854775807
        found = c.execute("""SELECT m.id,m.role,m.content,m.traces,m.created_at,
                              f.rating AS feedback_rating,f.reason AS feedback_reason
                           FROM messages m LEFT JOIN message_feedback f
                             ON f.message_id=m.id AND f.user_id=m.user_id
                           WHERE m.user_id=? AND m.bot_id=? AND m.id<?
                           ORDER BY m.id DESC LIMIT ?""", (user["id"], bot_id, cursor, limit + 1)).fetchall()
        more = len(found) > limit
        page = list(reversed(found[:limit]))
        ids = [int(item["id"]) for item in page]
        att_map = {}
        if ids:
            marks = ",".join("?" for _ in ids)
            for attachment in c.execute(f"SELECT * FROM attachments WHERE user_id=? AND message_id IN ({marks}) ORDER BY created_at,id",
                                         (user["id"], *ids)):
                att_map.setdefault(int(attachment["message_id"]), []).append(attachments.public(dict(attachment)))
        messages = []
        for item in page:
            rating, reason = item["feedback_rating"], item["feedback_reason"]
            messages.append({"id": item["id"], "role": item["role"], "content": item["content"],
                             "traces": json.loads(item["traces"]) if item["traces"] else [],
                             "created_at": item["created_at"], "attachments": att_map.get(int(item["id"]), []),
                             "feedback": {"rating": rating, "reason": reason}
                             if item["role"] == "assistant" and rating is not None else None})
        next_before_id = int(page[0]["id"]) if more and page else None
        return {"revision": revision, "messages": messages, "next_before_id": next_before_id, "unchanged": False}


@router.get("/api/bots/{bot_id}/messages")
def messages_list(bot_id: int, limit: int = 100, user=Depends(current_user)):
    require_bot(user, bot_id)
    with db.tx() as c:
        rs = message_store.list_recent(c, user["id"], bot_id, min(limit, 500))
    att_map = attachments.for_messages(user["id"], [r["id"] for r in rs])
    for r in rs:
        r["traces"] = json.loads(r["traces"]) if r["traces"] else []
        r["attachments"] = [attachments.public(a) for a in att_map.get(r["id"], [])]
        rating = r.pop("feedback_rating", None)
        reason = r.pop("feedback_reason", None)
        r["feedback"] = {"rating": rating, "reason": reason} if r["role"] == "assistant" and rating is not None else None
    return {"messages": list(reversed(rs))}


@router.delete("/api/bots/{bot_id}/messages")
def messages_clear(bot_id: int, include_memories: bool = False, user=Depends(current_user)):
    """清空对话。总是删除该 Bot 的滚动摘要，已确认的记忆默认保留（Boss 决策 Q3）；
    include_memories=true 时再删除该 Bot 的「本 Bot 记忆」（全局资料保留）。
    记忆的 source_message_id 随外键置 NULL。尚未开始的摘要任务标为 skipped。"""
    require_bot(user, bot_id)
    keys = attachments.keys_for_bot(user["id"], bot_id)
    with db.tx() as c:
        message_store.clear_conversation(c, user["id"], bot_id)
    attachments.delete_files(keys)   # 先删库行（已提交），再删文件
    memory_jobs.skip_pending_summaries(user["id"], bot_id)
    deleted = memory.clear_summaries(user["id"], bot_id)
    if include_memories:
        deleted += memory.clear_for_bot(user["id"], bot_id)
    return {"ok": True, "deleted_memories": deleted}


@router.delete("/api/bots/{bot_id}/messages/{message_id}")
def messages_delete(bot_id: int, message_id: int, user=Depends(current_user)):
    """删除单条消息（物理删除，只删这一条，不连带同一轮的另一条）。按 user_id + bot_id + id 限定：
    别人的消息、别的 Bot 的消息与不存在的消息一律返回相同的 404。引用该消息的行由外键 / 触发器处理：
    memories.source_message_id、notifications.message_id 置 NULL，reminders.source_message_id 由触发器置 NULL；
    Trace 存在消息行内，随行删除。已提取的记忆不删除。
    图片（v12，设计稿 Q12）：attachments 行随外键级联删除（与消息同一事务），提交后立即删原图、缩略图（GIF 另有第一帧），
    与清空对话相同的顺序（先库后文件；文件删失败留给对账）。
    不先调 require_bot：WHERE 已含 user_id + bot_id，他人的 Bot / 消息与不存在的消息返回完全相同的 404（不泄露存在性）。
    SQL 只在 db 层：db.delete_message（repository.py）与 attachment_store.list_for_message（经 attachments.keys_for_message）。"""
    keys = attachments.keys_for_message(user["id"], bot_id, message_id)
    if not db.delete_message(user["id"], bot_id, message_id):
        raise HTTPException(404, "消息不存在")
    attachments.delete_files(keys)   # 先删库行（已提交），再删文件
    return {"ok": True}


@router.post("/api/bots/{bot_id}/chat")
async def chat(bot_id: int, body: ChatIn, user=Depends(current_user)):
    """SSE 流式对话。事件：delta / tool_start / tool_result / error / done（done 含 message_id、user_message_id、usage、memory_ids）"""
    bot = require_bot(user, bot_id)
    used, budget = db.token_budget(user["id"])
    if used >= budget:   # BUG-06：每用户每日 Token 预算（Token budget）服务端强制
        raise HTTPException(429, f"今日 Token 额度已用完（{used:,} / {budget:,}），请明天再试")
    try:
        attachments.check_pending(user["id"], bot_id, body.attachment_ids)
    except attachments.AttachmentError as e:
        raise HTTPException(e.status, e.message)

    async def gen():
        from ...services.notify import hub
        queue = hub.subscribe(user["id"])
        try:
            async for ev in run_chat(user["id"], bot, body.message.strip(), body.attachment_ids):
                yield f"event: {ev['event']}\ndata: {json.dumps(ev['data'], ensure_ascii=False)}\n\n"
                for note in hub.drain(queue):
                    yield f"event: notification\ndata: {json.dumps(note, ensure_ascii=False)}\n\n"
        finally:
            hub.unsubscribe(user["id"], queue)

    return StreamingResponse(gen(), media_type="text/event-stream",
                             headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})

# 陪玩使用独立、无工具、无持久化对话的模型路径。
from ...services.tetris_companion import CompanionIn, reply as companion_reply

@router.post('/api/bots/{bot_id}/tetris-companion')
async def tetris_companion(bot_id: int, body: CompanionIn, user=Depends(current_user)):
    bot = require_bot(user, bot_id)
    used, budget = db.token_budget(user['id'])
    if used >= budget:
        raise HTTPException(429, '今日额度已用完，仍可继续玩游戏')
    try:
        raw, usage = await companion_reply(bot, body)
    except Exception as exc:
        # 不向客户端泄露 provider、密钥或内部报错；取消请求不拦截。
        raise HTTPException(502, '陪玩回应暂时没连上，请稍后再试') from exc
    db.log_usage(user['id'], bot_id, 'game', usage)
    try:
        text = json.loads(raw).get('text', '').strip()
        if not text:
            raise ValueError('empty reply')
    except (ValueError, AttributeError, TypeError) as exc:
        raise HTTPException(502, '陪玩回应暂时没准备好，请稍后再试') from exc
    return {'text': text[:180 if body.event in ('chat', 'pause') else 60]}
