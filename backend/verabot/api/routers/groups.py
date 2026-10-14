"""Group CRUD and persisted turn lookup; model chat endpoints arrive in G2."""
import anyio
from fastapi import APIRouter, Depends, HTTPException, Query, Request

from ..deps import current_user
from ..group_schemas import GroupCreateIn, GroupMemberAddIn, GroupPatchIn
from ...db import group_store

router = APIRouter(prefix="/api/groups", tags=["groups"])

def require_group_v2(request: Request):
    if request.headers.get("X-VeraBot-Group-Protocol") != "2":
        raise HTTPException(426, {"code": "group_upgrade_required", "message": "请升级应用后继续使用群聊"})

def call(fn, *args, **kwargs):
    try: return fn(*args, **kwargs)
    except group_store.GroupStoreError as e:
        detail = {"code": e.code, "message": e.message}
        if e.turn_id is not None: detail["turn_id"] = e.turn_id
        raise HTTPException(e.status, detail) from e

@router.get("")
def list_groups(user=Depends(current_user)):
    return {"groups": call(group_store.list_groups, user["id"])}

@router.post("", status_code=201, dependencies=[Depends(require_group_v2)])
def create(body: GroupCreateIn, user=Depends(current_user)):
    return call(group_store.create_group, user["id"], body.name, body.bot_ids)

@router.get("/{group_id}")
def detail(group_id: int, user=Depends(current_user)):
    return call(group_store.get_group, user["id"], group_id)

@router.patch("/{group_id}", dependencies=[Depends(require_group_v2)])
def update(group_id: int, body: GroupPatchIn, user=Depends(current_user)):
    return call(group_store.change_group, user["id"], group_id, body.model_dump(exclude_unset=True))

@router.post("/{group_id}/members", dependencies=[Depends(require_group_v2)])
def add_member(group_id: int, body: GroupMemberAddIn, user=Depends(current_user)):
    return call(group_store.add_member, user["id"], group_id, body.bot_id)

@router.delete("/{group_id}/members/{member_id}", dependencies=[Depends(require_group_v2)])
def remove_member(group_id: int, member_id: int, user=Depends(current_user)):
    return call(group_store.remove_member, user["id"], group_id, member_id)

@router.delete("/{group_id}", dependencies=[Depends(require_group_v2)])
def delete(group_id: int, user=Depends(current_user)):
    from ...db import group_execution_store
    call(group_store.get_group, user["id"], group_id)
    task_ids = call(group_execution_store.task_ids, user["id"], group_id)
    call(group_store.delete_group, user["id"], group_id)
    from ...services import group_worker
    for task_id in task_ids:
        group_worker.request_cancel(task_id)
    return {"ok": True}

@router.get("/{group_id}/messages")
def messages(group_id: int, before_id: int | None = Query(default=None, gt=0),
             limit: int = Query(default=50, ge=1, le=100), user=Depends(current_user)):
    return call(group_store.list_messages, user["id"], group_id, before_id, limit)

@router.get("/{group_id}/messages/sync")
def sync_messages(group_id: int, before_id: int | None = Query(default=None, gt=0),
                  limit: int = Query(default=100, ge=1, le=100),
                  expected_revision: int | None = Query(default=None, ge=0), user=Depends(current_user)):
    return call(group_store.sync_messages, user["id"], group_id, before_id, limit, expected_revision)

@router.delete("/{group_id}/messages", dependencies=[Depends(require_group_v2)])
def clear(group_id: int, user=Depends(current_user)):
    from ...db import group_execution_store
    call(group_store.get_group, user["id"], group_id)
    task_ids = call(group_execution_store.task_ids, user["id"], group_id)
    call(group_store.delete_group, user["id"], group_id, clear_only=True)
    from ...services import group_worker
    for task_id in task_ids:
        group_worker.request_cancel(task_id)
    return {"ok": True}

@router.get("/{group_id}/turns/{turn_id}")
def turn(group_id: int, turn_id: int, user=Depends(current_user)):
    return call(group_store.get_turn, user["id"], group_id, turn_id)

@router.post("/{group_id}/turns/{turn_id}/stop", dependencies=[Depends(require_group_v2)])
def stop(group_id: int, turn_id: int, user=Depends(current_user)):
    call(group_store.get_group, user["id"], group_id)
    raise HTTPException(426, {"code": "group_upgrade_required", "message": "请使用群任务停止接口"})

# Model execution stays request-bound. No detached jobs or automatic retries after disconnect.
from fastapi.responses import StreamingResponse
from ..group_schemas import GroupChatIn, GroupRetryIn
from ...agents import group_runtime
from ...services import groups as group_service, group_routing
import json


def budget(user_id):
    try: group_runtime.check_budget(user_id)
    except group_runtime.BudgetExhausted:
        raise HTTPException(429, {'code':'quota_exceeded','message':'今日额度已用完，请稍后继续。'})


def stream_turn(user_id, group, turn):
    async def content():
        generator=group_runtime.run(user_id,group,turn)
        try:
            async for event,data in generator:
                yield f'event: {event}\ndata: {json.dumps(data,ensure_ascii=False)}\n\n'
        finally:
            with anyio.CancelScope(shield=True):
                await generator.aclose()
                group_runtime.interrupted(user_id,group['id'],turn['id'])
    return StreamingResponse(content(),media_type='text/event-stream',headers={'X-Accel-Buffering':'no'})


@router.post('/{group_id}/chat', dependencies=[Depends(require_group_v2)])
def chat(group_id: int, body: GroupChatIn, user=Depends(current_user)):
    raise HTTPException(426, {"code": "group_upgrade_required", "message": "请使用群输入提交接口"})


@router.post('/{group_id}/messages/{message_id}/retry', dependencies=[Depends(require_group_v2)])
def retry(group_id: int, message_id: int, body: GroupRetryIn, user=Depends(current_user)):
    raise HTTPException(426, {"code": "group_upgrade_required", "message": "请使用群步骤重试接口"})
