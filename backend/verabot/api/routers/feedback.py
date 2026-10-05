"""消息反馈（👍 / 👎，M2 风格校准）。契约见 docs/design/MEMORY_GROWTH.md §11.1。

POST /api/messages/{id}/feedback 只能评本人的 assistant 消息：别人的消息、用户自己的消息、不存在的
消息一律返回相同的 404（不泄露存在性）。DELETE 撤销。👎 带理由且聚合到阈值时，响应里的 proposal 是
新生成的 style 记忆提议（客户端就地渲染确认卡片）；没有则是 null。
"""
from fastapi import APIRouter, Depends, HTTPException

from ... import db
from ...db import feedback_store, message_store
from ...services.memory import style
from ..deps import current_user
from ..schemas import FeedbackIn

router = APIRouter(tags=["feedback"])


def _own_assistant_message(c, user_id: int, message_id: int) -> dict:
    r = message_store.own_assistant(c, user_id, message_id)
    if r is None:
        raise HTTPException(404, {"message": "消息不存在", "code": "not_found"})
    return r


@router.post("/api/messages/{message_id}/feedback")
def feedback_set(message_id: int, body: FeedbackIn, user=Depends(current_user)):
    with db.tx() as c:
        m = _own_assistant_message(c, user["id"], message_id)
        feedback_store.upsert(c, user["id"], m["bot_id"], message_id, body.rating, body.reason)
        db.audit_in(c, user["id"], m["bot_id"], "message_feedback",
                    {"message_id": message_id, "rating": body.rating, "reason": body.reason})
    proposal = None
    if body.rating < 0 and body.reason:
        try:
            proposal = style.propose_from_feedback(user["id"], m["bot_id"], message_id)
        except Exception:   # noqa: BLE001 — 提议失败不影响评价本身
            proposal = None
    return {"ok": True, "message_id": message_id, "rating": body.rating, "reason": body.reason,
            "proposal": proposal}


@router.delete("/api/messages/{message_id}/feedback")
def feedback_delete(message_id: int, user=Depends(current_user)):
    with db.tx() as c:
        _own_assistant_message(c, user["id"], message_id)
        n = feedback_store.delete(c, user["id"], message_id)
    return {"ok": True, "deleted": n}
