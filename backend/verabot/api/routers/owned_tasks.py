from fastapi import APIRouter,Depends,HTTPException,Header,Query
from ..deps import current_user
from ..owned_task_schemas import CreateOwnedTask,Control,Input
from ...services.owned_tasks import service
from ...services.scheduled_tasks.contracts import TaskError
router=APIRouter(prefix='/api/owned-tasks',tags=['owned-tasks'])
def invoke(fn,*args):
 try:return fn(*args)
 except TaskError as e:raise HTTPException(e.status,{'code':e.code,'message':e.message}) from e
@router.post('',status_code=201)
def create(body:CreateOwnedTask,key:str|None=Header(None,alias='Idempotency-Key'),user=Depends(current_user)):
 return invoke(service.create,user['id'],body.model_dump(),key)
@router.get('')
def listing(bot_id:int|None=Query(None,gt=0),user=Depends(current_user)):return invoke(service.listing,user['id'],bot_id)
@router.get('/{tid}')
def detail(tid:int,user=Depends(current_user)):return invoke(service.detail,user['id'],tid)
@router.post('/{tid}/inputs')
def answer(tid:int,body:Input,key:str|None=Header(None,alias='Idempotency-Key'),user=Depends(current_user)):
 return invoke(service.submit_input,user['id'],tid,body.model_dump(exclude={'expected_version'}),key,body.expected_version)
@router.get('/{tid}/events')
def events(tid:int,after_id:int=Query(0,ge=0),user=Depends(current_user)):return invoke(service.events,user['id'],tid,after_id)
@router.post('/{tid}/{action}')
def control(tid:int,action:str,body:Control,user=Depends(current_user)):return invoke(service.control,user['id'],tid,action,body.expected_version,body.bot_id)

@router.get('/{tid}/events/stream')
async def stream(tid:int,after_id:int=Query(0,ge=0),user=Depends(current_user)):
 import asyncio,json
 from fastapi.responses import StreamingResponse
 invoke(service.detail,user['id'],tid)
 async def frames():
  cursor=after_id
  first=True
  while True:
   snap=service.detail(user['id'],tid)
   if first or snap['cursor']>cursor:
    first=False;cursor=snap['cursor']
    yield 'event: snapshot\ndata: '+json.dumps(snap,ensure_ascii=False)+'\n\n'
   if snap['state'] in ('completed','stopped','failed','interrupted'):return
   await asyncio.sleep(.5)
 return StreamingResponse(frames(),media_type='text/event-stream',headers={'Cache-Control':'no-store'})
