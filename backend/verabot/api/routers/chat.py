"""消息历史与流式对话（SSE）。"""
import json

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse

from ... import db
from ...agents.runtime import run_chat
from ...services import memory
from ...services.attachments import repo as attachments
from ..deps import current_user, require_bot
from ..schemas import ChatIn

router = APIRouter(tags=["chat"])


@router.get("/api/bots/{bot_id}/messages")
def messages_list(bot_id: int, limit: int = 100, user=Depends(current_user)):
    require_bot(user, bot_id)
    with db.tx() as c:
        rs = db.rows(c.execute("SELECT id, role, content, traces, created_at FROM messages WHERE user_id=? AND bot_id=?"
                               " ORDER BY id DESC LIMIT ?", (user["id"], bot_id, min(limit, 500))).fetchall())
    att_map = attachments.for_messages(user["id"], [r["id"] for r in rs])
    for r in rs:
        r["traces"] = json.loads(r["traces"]) if r["traces"] else []
        r["attachments"] = [attachments.public(a) for a in att_map.get(r["id"], [])]
    return {"messages": list(reversed(rs))}


@router.delete("/api/bots/{bot_id}/messages")
def messages_clear(bot_id: int, include_memories: bool = False, user=Depends(current_user)):
    """清空对话。默认**保留**记忆（Boss 决策 Q3）；include_memories=true 时同时删除该 Bot 的
    「本 Bot 记忆」与对话摘要（全局资料保留）。记忆的 source_message_id 随外键置 NULL。"""
    require_bot(user, bot_id)
    keys = attachments.keys_for_bot(user["id"], bot_id)
    with db.tx() as c:
        c.execute("DELETE FROM attachments WHERE user_id=? AND bot_id=?", (user["id"], bot_id))
        c.execute("DELETE FROM messages WHERE user_id=? AND bot_id=?", (user["id"], bot_id))
    attachments.delete_files(keys)   # 先删库行（已提交），再删文件
    out = {"ok": True, "deleted_memories": 0}
    if include_memories:
        out["deleted_memories"] = memory.clear_for_bot(user["id"], bot_id)
    return out


@router.post("/api/bots/{bot_id}/chat")
async def chat(bot_id: int, body: ChatIn, user=Depends(current_user)):
    """SSE 流式对话。事件：delta / tool_start / tool_result / error / done（done 含 message_id、usage、memory_ids）"""
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
