"""消息历史与流式对话（SSE）。"""
import json

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse

from ... import db
from ...agents.runtime import run_chat
from ...services import memory
from ..deps import current_user, require_bot
from ..schemas import ChatIn

router = APIRouter(tags=["chat"])


@router.get("/api/bots/{bot_id}/messages")
def messages_list(bot_id: int, limit: int = 100, user=Depends(current_user)):
    require_bot(user, bot_id)
    with db.tx() as c:
        rs = db.rows(c.execute("SELECT id, role, content, traces, created_at FROM messages WHERE user_id=? AND bot_id=?"
                               " ORDER BY id DESC LIMIT ?", (user["id"], bot_id, min(limit, 500))).fetchall())
    for r in rs:
        r["traces"] = json.loads(r["traces"]) if r["traces"] else []
    return {"messages": list(reversed(rs))}


@router.delete("/api/bots/{bot_id}/messages")
def messages_clear(bot_id: int, include_memories: bool = False, user=Depends(current_user)):
    """清空对话。默认**保留**记忆（Boss 决策 Q3）；include_memories=true 时同时删除该 Bot 的
    「本 Bot 记忆」与对话摘要（全局资料保留）。记忆的 source_message_id 随外键置 NULL。"""
    require_bot(user, bot_id)
    with db.tx() as c:
        c.execute("DELETE FROM messages WHERE user_id=? AND bot_id=?", (user["id"], bot_id))
    out = {"ok": True, "deleted_memories": 0}
    if include_memories:
        out["deleted_memories"] = memory.clear_for_bot(user["id"], bot_id)
    return out


@router.delete("/api/bots/{bot_id}/messages/{message_id}")
def messages_delete(bot_id: int, message_id: int, user=Depends(current_user)):
    """删除单条消息（物理删除，只删这一条，不连带同一轮的另一条）。按 user_id + bot_id + id 限定：
    别人的消息、别的 Bot 的消息与不存在的消息一律返回相同的 404。引用该消息的行由外键 / 触发器处理：
    memories.source_message_id、notifications.message_id 置 NULL，reminders.source_message_id 由触发器置 NULL；
    Trace 存在消息行内，随行删除。已提取的记忆不删除。
    不先调 require_bot：WHERE 已含 user_id + bot_id，他人的 Bot / 消息与不存在的消息返回完全相同的 404（不泄露存在性）。"""
    with db.tx() as c:
        n = c.execute("DELETE FROM messages WHERE id=? AND user_id=? AND bot_id=?",
                      (message_id, user["id"], bot_id)).rowcount
    if not n:
        raise HTTPException(404, "消息不存在")
    return {"ok": True}


@router.post("/api/bots/{bot_id}/chat")
async def chat(bot_id: int, body: ChatIn, user=Depends(current_user)):
    """SSE 流式对话。事件：delta / tool_start / tool_result / error / done（done 含 message_id、user_message_id、usage、memory_ids）"""
    bot = require_bot(user, bot_id)
    used, budget = db.token_budget(user["id"])
    if used >= budget:   # BUG-06：每用户每日 Token 预算（Token budget）服务端强制
        raise HTTPException(429, f"今日 Token 额度已用完（{used:,} / {budget:,}），请明天再试")

    async def gen():
        from ...services.notify import hub
        queue = hub.subscribe(user["id"])
        try:
            async for ev in run_chat(user["id"], bot, body.message.strip()):
                yield f"event: {ev['event']}\ndata: {json.dumps(ev['data'], ensure_ascii=False)}\n\n"
                for note in hub.drain(queue):
                    yield f"event: notification\ndata: {json.dumps(note, ensure_ascii=False)}\n\n"
        finally:
            hub.unsubscribe(user["id"], queue)

    return StreamingResponse(gen(), media_type="text/event-stream",
                             headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})
