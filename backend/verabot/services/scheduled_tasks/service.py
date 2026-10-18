import hashlib
import json
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
from ... import db
from ...db import scheduled_task_store as tasks, scheduled_run_store as runs
from . import clock, schedule
from .contracts import TaskError

def require(c,user_id,task_id):
    t=tasks.fetch(c,user_id,task_id)
    if not t or t['state']=='deleted':
        raise TaskError('not_found','任务不存在',404)
    return t

def public(task):
    out={k:v for k,v in task.items() if k not in ('authorized_tools_json','request_hash','idempotency_key','weekdays_json')}
    out['weekdays']=json.loads(task['weekdays_json'])
    return out

def key_valid(key):
    if not key or not 1<=len(key)<=128:
        raise TaskError('invalid_key','需要长度 1–128 的 Idempotency-Key')

def digest(payload):
    return hashlib.sha256(json.dumps(payload,sort_keys=True,ensure_ascii=False,separators=(',',':')).encode()).hexdigest()

def authorized(user_id,bot):
    from .policy import snapshot_tools
    return json.dumps(snapshot_tools(user_id,bot),sort_keys=True)

def create(user_id,payload,idempotency_key):
    key_valid(idempotency_key)
    hashed=digest(payload)
    now=clock.now()
    # Fast path also makes repeated creates valid after their initial start time.
    with db.tx() as c:
        old=tasks.by_key(c,user_id,idempotency_key)
        if old:
            if old['request_hash']!=hashed: raise TaskError('key_conflict','该请求标识已用于不同内容',409)
            return public(old)
    bot=db.get_bot(user_id,payload['bot_id'])
    if not bot: raise TaskError('not_found','Bot 不存在',404)
    when=schedule.validate(payload,now)
    tools=authorized(user_id,bot)
    if payload.get('execution_mode')=='owned':
        from ..primary_bot import get
        from ..owned_tasks.policy import snapshot
        if not get(user_id)['active_enabled']: raise TaskError('active_disabled','请先开启主动任务',409)
        tools=json.dumps(snapshot(user_id,bot),sort_keys=True)
    with db.tx(immediate=True) as c:
        old=tasks.by_key(c,user_id,idempotency_key)
        if old:
            if old['request_hash']!=hashed: raise TaskError('key_conflict','该请求标识已用于不同内容',409)
            return public(old)
        if not tasks.bot_exists(c,user_id,bot['id']):
            raise TaskError('not_found','Bot 不存在',404)
        tid=tasks.insert(c,dict(user_id=user_id,bot_id=bot['id'],title=payload['title'].strip(),
            instruction=payload['instruction'].strip(),execution_mode=payload.get('execution_mode','read_only'),state='active',**when,misfire_policy=payload.get('misfire_policy','skip'),
            authorized_tools_json=tools,idempotency_key=idempotency_key,request_hash=hashed,created_at=clock.iso(now),updated_at=clock.iso(now)))
        return public(tasks.fetch(c,user_id,tid))

def version_check(t,expected):
    if t['version']!=expected: raise TaskError('version_conflict','任务已更新，请刷新后再试',409)

def update(user_id,task_id,payload,expected_version):
    now=clock.now()
    with db.tx(immediate=True) as c:
        t=require(c,user_id,task_id); version_check(t,expected_version)
        values=dict(payload,version=t['version']+1,updated_at=clock.iso(now))
        schedule_keys={'start_at','timezone','repeat','weekdays'}
        if schedule_keys & payload.keys():
            try:
                old_local=clock.parse(t['start_at_utc']).astimezone(ZoneInfo(t['timezone']))
                new_local=old_local.replace(tzinfo=ZoneInfo(payload.get('timezone',t['timezone'])),fold=0)
            except ZoneInfoNotFoundError:
                raise TaskError('invalid_schedule','时区无效')
            merged=dict(start_at=new_local.isoformat(),timezone=t['timezone'],
                        repeat=t['repeat'],weekdays=json.loads(t['weekdays_json']))
            merged.update({k:payload[k] for k in schedule_keys & payload.keys()})
            if merged['repeat']!='weekly':
                merged['weekdays']=[]
            values.update(schedule.validate(merged,now,allow_past='start_at' not in payload))
            values['schedule_revision']=t['schedule_revision']+1
            if t['state']=='completed':
                values['state']='active'
            for k in ('start_at','weekdays'): values.pop(k,None)
        if 'instruction' in values or schedule_keys & payload.keys():
            runs.cancel_pending(c,task_id,now)
        tasks.update(c,user_id,task_id,values)
        return public(tasks.fetch(c,user_id,task_id))

def transition(user_id,task_id,action,expected_version):
    now=clock.now()
    ended=False
    with db.tx(immediate=True) as c:
        t=require(c,user_id,task_id); version_check(t,expected_version)
        values=dict(version=t['version']+1,updated_at=clock.iso(now))
        if action=='resume':
            if not t['bot_id']: raise TaskError('bot_deleted','负责 Bot 已删除')
            if t['state']!='paused': raise TaskError('invalid_state','只有暂停任务可以恢复',409)
            recorded=runs.high_water(c,task_id,t['schedule_revision'])
            after=max(now,recorded) if recorded else now
            nxt=schedule.next_after(t,after)
            values.update(state='active' if nxt else 'completed',next_run_at_utc=clock.iso(nxt) if nxt else None,pause_reason=None)
        elif action in ('pause','delete'):
            values.update(state='paused' if action=='pause' else 'deleted')
            if action=='delete':
                values['deleted_at']=clock.iso(now); ended=True
            runs.cancel_pending(c,task_id,now,include_running=True)
        else: raise TaskError('invalid_action','操作无效')
        tasks.update(c,user_id,task_id,values)
        result=public(tasks.fetch(c,user_id,task_id))
    if ended:
        from ..items.sync import on_task_ended
        on_task_ended(user_id,'scheduled',task_id)
    return result

def run_now(user_id,task_id,idempotency_key):
    key_valid(idempotency_key)
    with db.tx(immediate=True) as c:
        t=require(c,user_id,task_id)
        old=runs.by_key(c,user_id,task_id,idempotency_key)
        if old: return old
        if not t['bot_id']: raise TaskError('bot_deleted','负责 Bot 已删除')
        if runs.active(c,task_id): raise TaskError('task_busy','该任务已有一次执行进行中',409)
        now=clock.now()
        rid=runs.insert(c,t,now,now,trigger='manual',key=idempotency_key)
        if t.get('execution_mode')=='owned':
            from ..owned_tasks.schedules import enqueue_occurrence
            enqueue_occurrence(c,t,rid)
        return runs.fetch(c,user_id,task_id,rid)
