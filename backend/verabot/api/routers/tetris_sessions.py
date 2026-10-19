"""Read-only queries never advance play; POSTs acknowledge durable transactions."""
import json
from fastapi import APIRouter,Depends,HTTPException,Query,Request
from starlette.concurrency import run_in_threadpool
from ..deps import current_user
from ...db.tetris_session_store import SessionError
from ...services.tetris_sessions import service

router=APIRouter(prefix='/api/games/tetris/sessions',tags=['tetris'])

def _call(function,*args):
    try:return function(*args)
    except SessionError as error:raise HTTPException(error.status,error.detail) from error
async def _body(request):
    data=bytearray()
    async for chunk in request.stream():
        if len(data)+len(chunk)>65536:raise HTTPException(413,'request exceeds 64KiB')
        data.extend(chunk)
    try:
        body=json.loads(data)
        if not isinstance(body,dict):raise ValueError('object required')
        return body
    except (ValueError,UnicodeDecodeError) as error:raise HTTPException(422,'invalid JSON request') from error

@router.get('/capabilities')
def capabilities(user:dict=Depends(current_user)):
    return _call(service.capabilities)
@router.get('/operations/{request_id}')
def operation(request_id:str,user:dict=Depends(current_user)):
    return _call(service.operation,user['id'],request_id)
@router.get('/current')
def current(user:dict=Depends(current_user)):
    return _call(service.current,user['id'])
@router.get('/{session_id}')
def get(session_id:str,afterVersion:int|None=Query(default=None,ge=0),afterEventSequence:int|None=Query(default=None,ge=0),user:dict=Depends(current_user)):
    return _call(service.get,user['id'],session_id,afterEventSequence)
@router.post('')
async def create(request:Request,user:dict=Depends(current_user)):
    body=await _body(request)
    return await run_in_threadpool(_call,service.create,user['id'],body)
@router.post('/{session_id}/commands')
async def command(session_id:str,request:Request,user:dict=Depends(current_user)):
    body=await _body(request)
    return await run_in_threadpool(_call,service.command,user['id'],session_id,body)
