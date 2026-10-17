"""Authenticated personal Feed REST API. Refresh only queues durable work."""
from fastapi import APIRouter,Depends,HTTPException,Query
from ..deps import current_user
from ..feed_schemas import PlanInput,SuggestInput,SourceInput,SourcePatch,StatePatch,Kind
from ...services.feed import service,catalog
router=APIRouter(prefix='/api/feed',tags=['feed'])

def invoke(fn,*args,**kwargs):
    try: return fn(*args,**kwargs)
    except service.FeedError as e: raise HTTPException(e.status,e.message) from e

def bounded_topics(body):
    if any(not t or len(t)>80 for t in body.topics+getattr(body,'excluded_topics',[])):
        raise HTTPException(422,'主题应为 1–80 字')
    if any(b<=0 for b in body.bot_ids): raise HTTPException(422,'Bot ID 无效')

@router.get('/plan')
def plan(user=Depends(current_user)): return service.plan(user['id'])
@router.put('/plan')
def put_plan(body:PlanInput,user=Depends(current_user)):
    bounded_topics(body)
    return invoke(service.put_plan,user['id'],body.model_dump())
@router.post('/plan/suggest')
def suggest(body:SuggestInput,user=Depends(current_user)):
    bounded_topics(body)
    return invoke(service.suggest,user['id'],body.bot_ids,body.topics,body.use_memory)
@router.get('/catalog')
def directory(user=Depends(current_user)): return {'sources':catalog.catalog()}
@router.get('/sources')
def sources(user=Depends(current_user)): return {'sources':service.sources(user['id'])}
@router.post('/sources')
def add_source(body:SourceInput,user=Depends(current_user)): return invoke(service.add_source,user['id'],body.model_dump())
@router.patch('/sources/{source_id}')
def toggle_source(source_id:int,body:SourcePatch,user=Depends(current_user)): return invoke(service.toggle_source,user['id'],source_id,body.enabled)
@router.post('/refresh')
def refresh(user=Depends(current_user)): return {'queued':service.refresh(user['id'])}
@router.get('/items')
def items(cursor:str|None=None,limit:int=Query(20,ge=1,le=100),kind:Kind|None=None,bot_id:int|None=Query(None,gt=0),saved_only:bool=False,user=Depends(current_user)):
    return invoke(service.items,user['id'],cursor=cursor,limit=limit,kind=kind,bot_id=bot_id,saved_only=saved_only)
@router.get('/items/{item_id}')
def item(item_id:int,user=Depends(current_user)): return invoke(service.item,user['id'],item_id)
@router.patch('/items/{item_id}/state')
def state(item_id:int,body:StatePatch,user=Depends(current_user)): return invoke(service.state,user['id'],item_id,body.model_dump(exclude_unset=True))
@router.get('/items/{item_id}/context')
def context(item_id:int,bot_id:int=Query(gt=0),user=Depends(current_user)): return invoke(service.context,user['id'],item_id,bot_id)
