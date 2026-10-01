"""长期记忆（Memories）HTTP API。业务规则在 services.memory；这里只做参数解析与错误映射。

所有接口需 Bearer JWT，所有查询带 user_id；他人或不存在的记忆 → 404「记忆不存在」（防枚举）。
需要区分原因的错误使用 {"detail": {"message": "…", "code": "…"}}。契约见 docs/design/MEMORY_GROWTH.md §5.5。
"""
from fastapi import APIRouter, Depends, HTTPException

from ...services import memory
from ...services.memory import MemoryServiceError
from ..deps import current_user, require_bot
from ..schemas import MemoryConfirmIn, MemoryIn, MemoryPatch, MemorySettingsIn

router = APIRouter(tags=["memories"])


def _run(fn, *a, **kw):
    try:
        return fn(*a, **kw)
    except MemoryServiceError as e:
        raise HTTPException(e.status, e.detail())


def _bad(message: str):
    raise HTTPException(422, {"message": message, "code": "invalid_query"})


@router.get("/api/memories")
def memories_list(status: str = "active", scope: str | None = None, bot_id: int | None = None, ids: str | None = None,
                  visible_to: int | None = None, limit: int = 200, before_id: int | None = None,
                  user=Depends(current_user)):
    """status：逗号分隔（proposed / candidate / active / rejected / expired，或 all）；visible_to：某 Bot 能看到的记忆。"""
    statuses = memory.STATUSES if status == "all" else tuple(s.strip() for s in status.split(",") if s.strip())
    if not statuses or any(s not in memory.STATUSES for s in statuses):
        _bad("status 取值非法")
    if scope is not None and scope not in ("global", "bot", "summary"):
        _bad("scope 取值非法")
    id_list = None
    if ids:
        try:
            id_list = [int(x) for x in ids.split(",") if x.strip()]
        except ValueError:
            _bad("ids 必须是逗号分隔的整数")
        if len(id_list) > 50:
            _bad("ids 最多 50 个")
    if bot_id is not None:
        require_bot(user, bot_id)
    vis = require_bot(user, visible_to) if visible_to is not None else None
    return memory.list_memories(user["id"], statuses=statuses, scope=scope, bot_id=bot_id, ids=id_list,
                                visible_to=vis, limit=limit, before_id=before_id)


@router.get("/api/memories/{memory_id}")
def memories_get(memory_id: int, user=Depends(current_user)):
    return _run(memory.get_memory, user["id"], memory_id)


@router.post("/api/memories", status_code=201)
def memories_create(body: MemoryIn, user=Depends(current_user)):
    return _run(memory.create, user["id"], content=body.content, type=body.type, scope=body.scope, bot_id=body.bot_id)


@router.patch("/api/memories/{memory_id}")
def memories_patch(memory_id: int, body: MemoryPatch, user=Depends(current_user)):
    return _run(memory.update, user["id"], memory_id, content=body.content, type=body.type, scope=body.scope,
                bot_id=body.bot_id)


@router.delete("/api/memories/{memory_id}")
def memories_delete(memory_id: int, user=Depends(current_user)):
    return _run(memory.delete, user["id"], memory_id)


@router.delete("/api/memories")
def memories_clear(scope: str = "all", bot_id: int | None = None, confirm: bool = False, user=Depends(current_user)):
    if not confirm:
        raise HTTPException(400, {"message": "清空记忆需要 confirm=true", "code": "confirm_required"})
    return {"ok": True, "deleted": _run(memory.clear, user["id"], scope, bot_id)}


@router.post("/api/memories/{memory_id}/confirm")
def memories_confirm(memory_id: int, body: MemoryConfirmIn | None = None, user=Depends(current_user)):
    return _run(memory.confirm, user["id"], memory_id, body.content if body else None)


@router.post("/api/memories/{memory_id}/reject")
def memories_reject(memory_id: int, user=Depends(current_user)):
    return _run(memory.reject, user["id"], memory_id)


@router.get("/api/memory/settings")
def memory_settings(user=Depends(current_user)):
    return memory.settings(user["id"])


@router.patch("/api/memory/settings")
def memory_settings_patch(body: MemorySettingsIn, user=Depends(current_user)):
    return memory.set_enabled(user["id"], body.enabled)
