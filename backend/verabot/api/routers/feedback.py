"""消息反馈：POST / DELETE /api/messages/{id}/feedback。

只能评本人的 assistant 消息；他人、用户消息、不存在一律 404。
"""
from fastapi import APIRouter, Depends, HTTPException

from ...services.memory import feedback as feedback_svc
from ...services.memory.errors import MemoryServiceError
from ..deps import current_user
from ..schemas import FeedbackIn

router = APIRouter(tags=["feedback"])


def _run(fn, *a, **kw):
    try:
        return fn(*a, **kw)
    except MemoryServiceError as e:
        raise HTTPException(e.status, e.detail())


@router.post("/api/messages/{message_id}/feedback")
def feedback_set(message_id: int, body: FeedbackIn, user=Depends(current_user)):
    return _run(feedback_svc.submit, user["id"], message_id, body.rating, body.reason)


@router.delete("/api/messages/{message_id}/feedback")
def feedback_clear(message_id: int, user=Depends(current_user)):
    return _run(feedback_svc.clear, user["id"], message_id)
