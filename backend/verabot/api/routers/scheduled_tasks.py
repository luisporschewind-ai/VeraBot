import json
from fastapi import APIRouter, Depends, Header, HTTPException, Query
from ... import db
from ...db import scheduled_task_store as tasks, scheduled_run_store as runs
from ...services.scheduled_tasks import service
from ...services.scheduled_tasks.contracts import TaskError
from ..deps import current_user
from ..scheduled_task_schemas import CreateTask, UpdateTask, Version

router=APIRouter(prefix='/api/scheduled-tasks',tags=['scheduled-tasks'])

def invoke(fn,*args,**kwargs):
    try: return fn(*args,**kwargs)
    except TaskError as e: raise HTTPException(e.status,{'code':e.code,'message':e.message}) from e

def run_public(r):
    result={k:v for k,v in r.items() if k not in ('lease_token','lease_owner','task_snapshot_json','idempotency_key','request_hash')}
    return result

@router.post('',status_code=201)
def create(body:CreateTask,key:str|None=Header(default=None,alias='Idempotency-Key'),user=Depends(current_user)):
    return invoke(service.create,user['id'],body.model_dump(),key)

@router.get('')
def listing(user=Depends(current_user),state:str|None=None,bot_id:int|None=None,before_id:int|None=Query(None,gt=0),limit:int=Query(20,ge=1,le=100)):
    with db.tx() as c:
        found=tasks.list_tasks(c,user['id'],state=state,bot_id=bot_id,before_id=before_id,limit=limit)
    return {'tasks':[service.public(t) for t in found],'next_cursor':found[-1]['id'] if len(found)==limit else None}

@router.get('/{task_id}')
def detail(task_id:int,user=Depends(current_user)):
    with db.tx() as c:
        t=invoke(service.require,c,user['id'],task_id)
        latest=runs.list_runs(c,user['id'],task_id,limit=1)
    return dict(service.public(t),latest_run=run_public(latest[0]) if latest else None)

@router.patch('/{task_id}')
def update(task_id:int,body:UpdateTask,user=Depends(current_user)):
    payload=body.model_dump(exclude_unset=True); version=payload.pop('expected_version')
    if any(v is None for v in payload.values()): raise HTTPException(422,'修改字段不能为 null')
    return invoke(service.update,user['id'],task_id,payload,version)

@router.post('/{task_id}/pause')
def pause(task_id:int,body:Version,user=Depends(current_user)):
    return invoke(service.transition,user['id'],task_id,'pause',body.expected_version)

@router.post('/{task_id}/resume')
def resume(task_id:int,body:Version,user=Depends(current_user)):
    return invoke(service.transition,user['id'],task_id,'resume',body.expected_version)

@router.delete('/{task_id}')
def delete(task_id:int,body:Version,user=Depends(current_user)):
    return invoke(service.transition,user['id'],task_id,'delete',body.expected_version)

@router.post('/{task_id}/run',status_code=202)
def run_now(task_id:int,key:str|None=Header(default=None,alias='Idempotency-Key'),user=Depends(current_user)):
    return run_public(invoke(service.run_now,user['id'],task_id,key))

@router.get('/{task_id}/runs')
def history(task_id:int,user=Depends(current_user),before_id:int|None=Query(None,gt=0),limit:int=Query(20,ge=1,le=100)):
    with db.tx() as c:
        # Deleted tasks retain accessible history, but not editable definitions.
        if not tasks.fetch(c,user['id'],task_id): raise HTTPException(404,'任务不存在')
        found=runs.list_runs(c,user['id'],task_id,before_id,limit)
    return {'runs':[run_public(r) for r in found],'next_cursor':found[-1]['id'] if len(found)==limit else None}

@router.get('/{task_id}/runs/{run_id}')
def run_detail(task_id:int,run_id:int,user=Depends(current_user)):
    with db.tx() as c:
        r=runs.fetch(c,user['id'],task_id,run_id)
        if not r: raise HTTPException(404,'执行不存在')
        attempts=runs.attempts(c,run_id)
    for a in attempts:
        a['usage']=json.loads(a.pop('usage_json') or '{}')
        a['trace_summary']=json.loads(a.pop('trace_summary_json') or '[]')
    return dict(run_public(r),attempts=attempts)
