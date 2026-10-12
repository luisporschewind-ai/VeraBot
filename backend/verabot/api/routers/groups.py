"""Group CRUD and persisted turn lookup; model chat endpoints arrive in G2."""
import anyio
from fastapi import APIRouter, Depends, HTTPException, Query

from ..deps import current_user
from ..group_schemas import GroupCreateIn, GroupPatchIn
from ...db import group_store

router = APIRouter(prefix="/api/groups", tags=["groups"])

def call(fn, *args, **kwargs):
    try: return fn(*args, **kwargs)
    except group_store.GroupStoreError as e:
        detail = {"code": e.code, "message": e.message}
        if e.turn_id is not None: detail["turn_id"] = e.turn_id
        raise HTTPException(e.status, detail) from e

@router.get("")
def list_groups(user=Depends(current_user)):
    return {"groups": call(group_store.list_groups, user["id"])}

@router.post("", status_code=201)
def create(body: GroupCreateIn, user=Depends(current_user)):
    return call(group_store.create_group, user["id"], body.name, body.bot_ids, body.default_bot_id)

@router.get("/{group_id}")
def detail(group_id: int, user=Depends(current_user)):
    return call(group_store.get_group, user["id"], group_id)

@router.patch("/{group_id}")
def update(group_id: int, body: GroupPatchIn, user=Depends(current_user)):
    return call(group_store.change_group, user["id"], group_id, body.model_dump(exclude_unset=True))

@router.delete("/{group_id}")
def delete(group_id: int, user=Depends(current_user)):
    call(group_store.delete_group, user["id"], group_id)
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

@router.delete("/{group_id}/messages")
def clear(group_id: int, user=Depends(current_user)):
    call(group_store.delete_group, user["id"], group_id, clear_only=True)
    return {"ok": True}

@router.get("/{group_id}/turns/{turn_id}")
def turn(group_id: int, turn_id: int, user=Depends(current_user)):
    return call(group_store.get_turn, user["id"], group_id, turn_id)

@router.post("/{group_id}/turns/{turn_id}/stop")
def stop(group_id: int, turn_id: int, user=Depends(current_user)):
    return call(group_service.request_stop, user["id"], group_id, turn_id)

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


@router.post('/{group_id}/chat')
def chat(group_id: int, body: GroupChatIn, user=Depends(current_user)):
    group=call(group_store.get_group,user['id'],group_id)
    original=body.model_dump(mode='json')
    existing=call(group_store.existing_request,user['id'],group_id,body.client_request_id,original)
    if existing:
        raise HTTPException(409, {'code':'request_exists','message':'请求已存在','turn_id':existing})
    budget(user['id'])
    resolved=original
    if body.mode == 'auto':
        route=anyio.run(group_routing.resolve,user['id'],group,body.message)
        resolved={**original,**route}
    turn=call(group_store.claim_turn,user['id'],group_id,resolved,request_hash_payload=original)
    return stream_turn(user['id'],group,turn)


@router.post('/{group_id}/messages/{message_id}/retry')
def retry(group_id: int, message_id: int, body: GroupRetryIn, user=Depends(current_user)):
    group=call(group_store.get_group,user['id'],group_id)
    call(group_store.get_message,user['id'],group_id,message_id)
    if not call(group_store.existing_request,user['id'],group_id,body.client_request_id): budget(user['id'])
    turn=call(group_store.claim_retry,user['id'],group_id,message_id,str(body.client_request_id))
    return stream_turn(user['id'],group,turn)
