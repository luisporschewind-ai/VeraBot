import json
from ... import db
from ...db import owned_task_store as store
from ..scheduled_tasks.contracts import TaskError
from ..scheduled_tasks.service import digest,key_valid
from .. import primary_bot

def require(c,uid,tid):
 t=store.get(c,uid,tid)
 if not t:raise TaskError('not_found','任务不存在',404)
 return t

def public(c,t):
 result={k:v for k,v in t.items() if k not in ('authorization_json','request_key','request_hash','user_id')}
 result['steps']=[{k:v for k,v in s.items() if k in ('id','bot_id','kind','status','result_json','message_id')} for s in store.steps(c,t['id'])]
 result['waits']=store.waits(c,t['id'])
 result['cursor']=store.cursor(c,t['id'])
 return result

def create(uid,payload,key):
 key_valid(key);h=digest(payload)
 with db.tx(immediate=True) as c:
  old=store.by_key(c,uid,key)
  if old:
   if old['request_hash']!=h:raise TaskError('key_conflict','请求标识已用于不同内容',409)
   return public(c,old)
  s=primary_bot.get(uid)
  if not s['active_enabled']:raise TaskError('active_disabled','请先开启主动任务',409)
  bid=payload.get('bot_id') or s['primary_bot_id'];bot=db.get_bot(uid,bid) if bid else None
  if not bot:raise TaskError('not_found','Bot 不存在',404)
  from .policy import snapshot
  t=store.create(c,uid,bot,payload,key,h,snapshot(uid,bot,payload['goal']));return public(c,t)

def detail(uid,tid):
 with db.tx() as c:return public(c,require(c,uid,tid))
def listing(uid,bid=None):
 with db.tx() as c:return {'tasks':[public(c,t) for t in store.list_tasks(c,uid,bid)]}
def submit_input(uid,tid,payload,key,version):
 key_valid(key);h=digest(payload)
 with db.tx(immediate=True) as c:
  t=require(c,uid,tid);old=store.input_by_key(c,tid,key)
  if old:
   if old['request_hash']!=h:raise TaskError('key_conflict','请求标识已用于不同内容',409)
   return public(c,t)
  check_version(t,version)
  if not primary_bot.get(uid)['active_enabled']:raise TaskError('active_disabled','主动任务已关闭',409)
  try:t=store.answer(c,t,payload['message'],key,h)
  except ValueError as e:raise TaskError('invalid_state',str(e),409) from e
  return public(c,t)
def check_version(t,v):
 if t['version']!=v:raise TaskError('version_conflict','任务已更新，请刷新',409)
def control(uid,tid,action,version,bot_id=None):
 ended=False
 with db.tx(immediate=True) as c:
  t=require(c,uid,tid);check_version(t,version)
  if action=='stop':t=store.invalidate(c,t,'stopped','user_stopped');ended=True
  elif action in ('continue','transfer'):
   if t['state'] not in ('stopped','failed','interrupted','awaiting_user'):raise TaskError('invalid_state','当前任务不能继续或移交',409)
   if not primary_bot.get(uid)['active_enabled']:raise TaskError('active_disabled','主动任务已关闭',409)
   if action=='transfer':
    bot=db.get_bot(uid,bot_id) if bot_id else None
    if not bot:raise TaskError('not_found','Bot 不存在',404)
    from .policy import snapshot
    frozen=json.loads(t['authorization_json']);new=snapshot(uid,bot)
    auth={k:v for k,v in new.items() if frozen.get(k)==v}
    auth['__delegates']=list(set(frozen.get('__delegates',[])) & set(new.get('__delegates',[])))
    auth['__memory_ids']=frozen.get('__memory_ids',[])
    store.update_task(c,tid,dict(owner_bot_id=bot_id,owner_name=bot['name'],authorization_json=json.dumps(auth)))
   try:store.reopen_schedule(c,t)
   except ValueError as e:raise TaskError('schedule_busy',str(e),409) from e
   t=store.invalidate(c,require(c,uid,tid),'queued')
   store.reset_chain(c,tid)
   store.enqueue(c,t,{'continued':True})
  else:raise TaskError('invalid_action','无效操作',422)
  result=public(c,t)
 if ended:
  from ..items.sync import on_task_ended
  on_task_ended(uid,'owned',tid)
 return result
def events(uid,tid,after):
 with db.tx() as c:
  require(c,uid,tid)
  return {'events':[dict(e,payload=json.loads(e['payload_json'])) for e in store.events(c,uid,tid,after)]}
