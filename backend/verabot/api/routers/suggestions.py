"""记忆成长建议与快捷提问 API。"""
from fastapi import APIRouter, Depends, HTTPException

from ...services.memory import quick_prompts
from ...services.memory import suggestions as memory_suggestions
from ...services.reminders.service import ReminderError
from ..deps import current_user, require_bot

router = APIRouter(tags=["memory suggestions"])


@router.get("/api/bots/{bot_id}/suggestions")
def bot_suggestions(bot_id: int, user=Depends(current_user)):
    bot = require_bot(user, bot_id)
    return {"suggestions": memory_suggestions.list_for_bot(user["id"], bot)}


@router.post("/api/suggestions/{suggestion_id}/accept")
def suggestion_accept(suggestion_id: int, user=Depends(current_user)):
    try:
        result = memory_suggestions.accept(user["id"], suggestion_id)
    except ReminderError as exc:
        raise HTTPException(exc.status, {"message": exc.message, "code": exc.code}) from exc
    except ValueError as exc:
        if str(exc) == "suggestion_target_unavailable":
            raise HTTPException(404, {"message": "建议目标不存在", "code": "not_found"}) from exc
        raise HTTPException(422, {"message": "建议数据无效", "code": "invalid_suggestion"}) from exc
    if result is None:
        raise HTTPException(404, {"message": "建议不存在", "code": "not_found"})
    return result


@router.post("/api/suggestions/{suggestion_id}/dismiss")
def suggestion_dismiss(suggestion_id: int, user=Depends(current_user)):
    result = memory_suggestions.decide(user["id"], suggestion_id, "dismissed")
    if result is None:
        raise HTTPException(404, {"message": "建议不存在", "code": "not_found"})
    return {"id": result["id"], "status": result["status"]}


@router.get("/api/bots/{bot_id}/quick-prompts")
def bot_quick_prompts(bot_id: int, user=Depends(current_user)):
    require_bot(user, bot_id)
    return {"prompts": quick_prompts.for_bot(user["id"], bot_id)}
