import asyncio
import json
from fastapi import APIRouter,Depends,HTTPException,Query,Request
from fastapi.responses import StreamingResponse
from ...db import conversation_activity_store as store
from ..deps import current_user
from ..chat_task_schemas import ReadInput
router=APIRouter(tags=['conversation-activity'])
def http(e):return HTTPException(e.status,{'code':e.code,'message':e.message})
@router.get('/api/conversations/activity')
def activity(user=Depends(current_user)):return store.snapshot(user['id'])
@router.post('/api/conversations/{kind}/{conversation_id}/read')
def read(kind:str,conversation_id:int,body:ReadInput,user=Depends(current_user)):
    try:return store.read(user['id'],kind,conversation_id,body.generation,[m.model_dump() for m in body.messages])
    except store.ActivityError as e:raise http(e)
@router.get('/api/conversations/events')
async def events(request:Request,after_id:int=Query(0,ge=0),user=Depends(current_user)):
    try:store.events(user['id'],after_id)
    except store.ActivityError as e:raise http(e)
    async def observe():
        cursor=after_id
        while not await request.is_disconnected():
            try:batch=store.events(user['id'],cursor)
            except store.ActivityError as e:
                yield 'event: resync_required\ndata: '+json.dumps({'code':e.code})+'\n\n';return
            for item in batch:
                cursor=item['id'];yield f"id: {cursor}\nevent: {item['event']}\ndata: {json.dumps(item['data'],ensure_ascii=False)}\n\n"
            if not batch:yield ': keepalive\n\n'
            await asyncio.sleep(.5)
    return StreamingResponse(observe(),media_type='text/event-stream')
