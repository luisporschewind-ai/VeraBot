import asyncio
import json
from fastapi import APIRouter,Depends,HTTPException,Query,Request
from fastapi.responses import JSONResponse,StreamingResponse
from ... import db
from ...db import chat_reply_store as store
from ...services.chat_tasks import service
from ...services.attachments.repo import AttachmentError
from ..deps import current_user,require_bot
from ..chat_task_schemas import ChatInput,StopInput,AnswerInput
router=APIRouter(tags=['chat-tasks'])

def http(e):return HTTPException(e.status,{'code':getattr(e,'code',None),'message':e.message})

@router.post('/api/bots/{bot_id}/chat/inputs')
def submit(bot_id:int,body:ChatInput,user=Depends(current_user)):
    require_bot(user,bot_id)
    try:
        result,new=service.submit(user['id'],bot_id,body.model_dump())
        return JSONResponse(result,status_code=202 if new else 200)
    except (store.ChatTaskError,AttachmentError) as e:raise http(e)

@router.get('/api/bots/{bot_id}/chat/inputs/{request_id}')
def receipt(bot_id:int,request_id:str,user=Depends(current_user)):
    require_bot(user,bot_id)
    with db.tx() as c:r=store.receipt(c,user['id'],bot_id,request_id)
    if not r:raise HTTPException(404,{'code':'not_accepted','message':'尚未接收该请求'})
    return json.loads(r['response_json'])

@router.get('/api/bots/{bot_id}/chat/execution')
def execution(bot_id:int,user=Depends(current_user)):
    try:return store.execution(user['id'],bot_id)
    except store.ChatTaskError as e:raise http(e)
    except store.activity.ActivityError as e:raise http(e)

@router.post('/api/bots/{bot_id}/chat/tasks/{task_id}/stop')
def stop(bot_id:int,task_id:int,body:StopInput,user=Depends(current_user)):
    try:
        with db.tx(immediate=True) as c:return store.control(c,user['id'],bot_id,task_id,body.model_dump())
    except store.ChatTaskError as e:raise http(e)

@router.post('/api/bots/{bot_id}/chat/tasks/{task_id}/inputs')
def answer(bot_id:int,task_id:int,body:AnswerInput,user=Depends(current_user)):
    try:
        with db.tx(immediate=True) as c:return store.control(c,user['id'],bot_id,task_id,body.model_dump(),answer=True)
    except store.ChatTaskError as e:raise http(e)

@router.get('/api/bots/{bot_id}/chat/events')
async def events(bot_id:int,request:Request,after_id:int=Query(0,ge=0),user=Depends(current_user)):
    try:store.events(user['id'],bot_id,after_id)
    except store.activity.ActivityError as e:raise http(e)
    async def observe():
        cursor=after_id
        while not await request.is_disconnected():
            try:batch=store.events(user['id'],bot_id,cursor)
            except store.activity.ActivityError as e:
                yield 'event: resync_required\ndata: '+json.dumps({'code':e.code})+'\n\n';return
            for item in batch:
                cursor=item['id'];yield f"id: {cursor}\nevent: {item['event']}\ndata: {json.dumps(item['data'],ensure_ascii=False)}\n\n"
            if not batch:yield ': keepalive\n\n'
            await asyncio.sleep(.5)
    return StreamingResponse(observe(),media_type='text/event-stream')
