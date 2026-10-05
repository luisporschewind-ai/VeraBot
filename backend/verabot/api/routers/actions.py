"""待确认操作 API：GET 列表 / 单条，POST confirm / cancel。与 MCP M3、后续 Gmail 共用。"""
from fastapi import APIRouter, Depends, HTTPException, Query

from ...services.actions import ActionError, cancel, confirm, get_action, list_actions
from ..deps import current_user

router = APIRouter(tags=["pending-actions"])


def _http(exc: ActionError) -> HTTPException:
    detail = {"message": exc.message, "code": exc.code} if exc.code else exc.message
    return HTTPException(exc.status, detail)


@router.get("/api/pending-actions")
def pending_list(
    status: str | None = Query("pending"),
    bot_id: int | None = None,
    user=Depends(current_user),
):
    """status=pending|done|cancelled|expired|failed|unknown；传 all 不过滤。"""
    filt = None if status in (None, "", "all") else status
    return {"actions": list_actions(user["id"], status=filt, bot_id=bot_id)}


@router.get("/api/pending-actions/{action_id}")
def pending_get(action_id: int, user=Depends(current_user)):
    try:
        return get_action(user["id"], action_id)
    except ActionError as exc:
        raise _http(exc) from exc


@router.post("/api/pending-actions/{action_id}/confirm")
def pending_confirm(action_id: int, user=Depends(current_user)):
    try:
        return confirm(user["id"], action_id)
    except ActionError as exc:
        raise _http(exc) from exc


@router.post("/api/pending-actions/{action_id}/cancel")
def pending_cancel(action_id: int, user=Depends(current_user)):
    try:
        return cancel(user["id"], action_id)
    except ActionError as exc:
        raise _http(exc) from exc
