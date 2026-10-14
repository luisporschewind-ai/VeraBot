"""All durable task writes are transaction-scoped and fenced by version/lease."""
import json, uuid
from datetime import datetime,timedelta,timezone
from .database import now_iso
TERMINAL={'completed','stopped','failed','interrupted'}
def stamp_after(seconds,now=None):return (datetime.fromisoformat(now or now_iso())+timedelta(seconds=seconds)).isoformat(timespec='seconds')
def row(r):return dict(r) if r else None
def get(c,user_id,task_id):return row(c.execute('SELECT * FROM owned_tasks WHERE id=? AND user_id=?',(task_id,user_id)).fetchone())
def by_key(c,user_id,key):return row(c.execute('SELECT * FROM owned_tasks WHERE user_id=? AND request_key=?',(user_id,key)).fetchone())
def list_tasks(c,user_id,bot_id=None):
 return [dict(r) for r in c.execute('SELECT * FROM owned_tasks WHERE user_id=?'+(' AND owner_bot_id=?' if bot_id else '')+' ORDER BY id DESC LIMIT 100',(user_id,bot_id) if bot_id else (user_id,))]
def event(c,t,kind,payload=None):
 c.execute('INSERT INTO owned_events(task_id,user_id,version,kind,payload_json,created_at) VALUES (?,?,?,?,?,?)',(t['id'],t['user_id'],t['version'],kind,json.dumps(payload or {},ensure_ascii=False),now_iso()))
def steps(c,tid):return [dict(r) for r in c.execute('SELECT * FROM owned_steps WHERE task_id=? ORDER BY id',(tid,))]
def waits(c,tid):return [dict(r) for r in c.execute('SELECT * FROM owned_waits WHERE task_id=? AND resolved_at IS NULL ORDER BY id',(tid,))]
def events(c,uid,tid,after):return [dict(r) for r in c.execute('SELECT * FROM owned_events WHERE user_id=? AND task_id=? AND id>? ORDER BY id LIMIT 100',(uid,tid,after))]
def enqueue(c,t,input,kind='owner',bot_id=None,key=None):
 return c.execute('INSERT INTO owned_steps(task_id,bot_id,version,kind,input_json,action_key,available_at,created_at) VALUES (?,?,?,?,?,?,?,?)',(t['id'],bot_id or t['owner_bot_id'],t['version'],kind,json.dumps(input,ensure_ascii=False),key or uuid.uuid4().hex,now_iso(),now_iso())).lastrowid

def create(c,uid,bot,payload,key,hashed,authorization):
 now=now_iso()
 tid=c.execute('INSERT INTO owned_tasks(user_id,owner_bot_id,owner_name,goal,completion_criteria,state,authorization_json,token_limit,created_at,updated_at,request_key,request_hash) VALUES (?,?,?,?,?,\'queued\',?,?,?,?,?,?)',(uid,bot['id'],bot['name'],payload['goal'],payload['completion_criteria'],json.dumps(authorization),payload.get('token_limit',20000),now,now,key,hashed)).lastrowid
 from .conversation_activity_store import generation
 c.execute('UPDATE owned_tasks SET delivery_generation=? WHERE id=?',(generation(c,uid,'private',bot['id']),tid))
 t=get(c,uid,tid);enqueue(c,t,{});event(c,t,'created');return t

def invalidate(c,t,state,code=None):
 c.execute("UPDATE owned_steps SET status='cancelled' WHERE task_id=? AND status IN ('queued','running','retry_wait')",(t['id'],))
 c.execute('UPDATE owned_waits SET resolved_at=? WHERE task_id=? AND resolved_at IS NULL',(now_iso(),t['id']))
 c.execute('UPDATE owned_tasks SET version=version+1,state=?,blocker_code=?,updated_at=? WHERE id=?',(state,code,now_iso(),t['id']))
 t=get(c,t['user_id'],t['id']);event(c,t,state);return t

def disable_user(c,uid):
 for t in list_tasks(c,uid):
  if t['state'] not in TERMINAL:invalidate(c,t,'stopped','active_disabled')
def delete_bot(c,uid,bid):
 for t in list_tasks(c,uid,bid):
  if t['state'] not in TERMINAL:invalidate(c,t,'stopped','bot_deleted')

def live(c,step):
 return row(c.execute("SELECT t.* FROM owned_steps s JOIN owned_tasks t ON t.id=s.task_id JOIN bots b ON b.id=s.bot_id AND b.user_id=t.user_id JOIN primary_bot_settings p ON p.user_id=t.user_id WHERE s.id=? AND s.status='running' AND s.lease_token=? AND s.version=? AND t.version=s.version AND s.lease_expires_at>? AND t.state='running' AND p.active_enabled=1 AND (t.scheduled_run_id IS NULL OR EXISTS (SELECT 1 FROM scheduled_task_runs r WHERE r.id=t.scheduled_run_id AND r.state='retry_wait' AND r.error_code='owned_active' AND r.cancel_requested=0))",(step['id'],step['lease_token'],step['version'],now_iso())).fetchone())
def recover(c,now):
 stale=[dict(r) for r in c.execute("SELECT t.* FROM owned_tasks t JOIN owned_steps s ON s.task_id=t.id WHERE s.status='running' AND s.lease_expires_at<=?",(now,))]
 for t in stale:
  for call in c.execute('SELECT id FROM owned_calls WHERE task_id=? AND usage_logged=0',(t['id'],)).fetchall():record_call(c,call[0],None,0)
  invalidate(c,t,'interrupted','execution_unknown')
 # Deletion can happen outside the API; fence orphaned tasks before another claim.
 for t in c.execute("SELECT * FROM owned_tasks WHERE owner_bot_id IS NULL AND state NOT IN ('completed','stopped','failed','interrupted')").fetchall():invalidate(c,dict(t),'stopped','bot_deleted')
 return len(stale)
def claim_next(c,owner,now):
 recover(c,now)
 r=row(c.execute("SELECT s.* FROM owned_steps s JOIN owned_tasks t ON t.id=s.task_id JOIN primary_bot_settings p ON p.user_id=t.user_id WHERE s.status IN ('queued','retry_wait') AND s.available_at<=? AND s.version=t.version AND t.state IN ('queued','retry_wait') AND p.active_enabled=1 ORDER BY s.id LIMIT 1",(now,)).fetchone())
 if not r:return None
 token=uuid.uuid4().hex;exp=stamp_after(90,now)
 c.execute("UPDATE owned_steps SET status='running',lease_token=?,lease_expires_at=?,attempts=attempts+1 WHERE id=?",(token,exp,r['id']))
 c.execute("UPDATE owned_tasks SET state='running',updated_at=? WHERE id=?",(now,r['task_id']))
 r.update(status='running',lease_token=token,lease_expires_at=exp,attempts=r['attempts']+1)
 t=row(c.execute('SELECT * FROM owned_tasks WHERE id=?',(r['task_id'],)).fetchone());event(c,t,'running',{'step_id':r['id']});return r

def renew(c,step):
 if not live(c,step):return False
 c.execute('UPDATE owned_steps SET lease_expires_at=? WHERE id=?',(stamp_after(90),step['id']));return True

def commit_step(c,step,result):
 t=live(c,step)
 if not t:return False
 action=result['action'];text=result.get('text','')
 if result.get('tainted'):c.execute('UPDATE owned_tasks SET tainted=1 WHERE id=?',(t['id'],))
 if action=='consult':
  target=result['bot_id']
  b=row(c.execute('SELECT * FROM bots WHERE id=? AND user_id=?',(target,t['user_id'])).fetchone())
  owner=row(c.execute('SELECT * FROM bots WHERE id=? AND user_id=?',(t['owner_bot_id'],t['user_id'])).fetchone())
  if 'ask_bot' not in json.loads(owner.get('allowed_tools') or '[]'):raise ValueError('未授权咨询能力')
  if step['kind']=='consult' or not b or target==owner['id'] or target not in json.loads(owner.get('delegate_to') or '[]') or not b['accept_delegation']:
   raise ValueError('该咨询未获授权')
  if target not in json.loads(t['authorization_json']).get('__delegates',[]):raise ValueError('该咨询不在任务原授权范围')
  if result.get('tainted') or t['tainted']:raise ValueError('读取外部结果后不可委派')
 elif action not in ('completed','await_user','await_approval','retry_wait','failed','interrupted'):raise ValueError('无效任务动作')
 if not isinstance(text,str) or not text.strip():raise ValueError('步骤缺少结果或问题')
 c.execute('UPDATE owned_steps SET status=?,result_json=? WHERE id=?',('completed' if action not in ('failed','interrupted','retry_wait') else action,json.dumps(result,ensure_ascii=False),step['id']))
 state={'completed':'completed','consult':'queued','await_user':'awaiting_user','await_approval':'awaiting_approval','retry_wait':'retry_wait','failed':'failed','interrupted':'interrupted'}[action]
 if step['kind']=='consult' and action=='completed':
  state='queued';enqueue(c,t,{'consult_result':text,'bot_id':step['bot_id']})
 elif action=='consult':enqueue(c,t,{'question':text},kind='consult',bot_id=result['bot_id'])
 elif action in ('await_user','await_approval'):
  c.execute('INSERT INTO owned_waits(task_id,step_id,version,kind,question,action_id) VALUES (?,?,?,?,?,?)',(t['id'],step['id'],t['version'],action,text,result.get('action_id')))
 elif action=='retry_wait':
  c.execute('UPDATE owned_steps SET available_at=? WHERE id=?',(stamp_after((30,120)[min(step['attempts']-1,1)]),step['id']))
 c.execute('UPDATE owned_tasks SET state=?,blocker_code=?,updated_at=? WHERE id=?',(state,result.get('blocker_code'),now_iso(),t['id']))
 event(c,t,state,{'step_id':step['id']});return True

def input_by_key(c,tid,key):return row(c.execute('SELECT * FROM owned_inputs WHERE task_id=? AND request_key=?',(tid,key)).fetchone())
def answer(c,t,message,key,hashed):
 old=waits(c,t['id'])
 if not old:raise ValueError('任务没有等待回答')
 if t['state']=='awaiting_approval':raise ValueError('请先处理操作确认')
 t=invalidate(c,t,'queued')
 c.execute('INSERT INTO owned_inputs(task_id,request_key,request_hash,message,version) VALUES (?,?,?,?,?)',(t['id'],key,hashed,message,t['version']))
 c.execute('UPDATE owned_tasks SET chain_calls=0,chain_output=0,chain_tools=0,chain_seconds=0 WHERE id=?',(t['id'],))
 enqueue(c,t,{'answer':message,'question':old[-1]['question']});return t

def history_context(c,tid):
 return [{'input':json.loads(r['input_json']),'result':json.loads(r['result_json'])} for r in c.execute("SELECT input_json,result_json FROM owned_steps WHERE task_id=? AND status='completed' AND result_json IS NOT NULL ORDER BY id",(tid,))][-12:]
def begin_call(c,step):
 t=live(c,step)
 if not t:raise ValueError('执行已过期')
 if t['chain_calls']>=6 or t['chain_output']>=2048 or t['chain_seconds']>=240 or t['used_tokens']+t['reserved_tokens']>=t['token_limit']:raise ValueError('任务已达到执行上限，请调整预算或停止')
 settings=row(c.execute('SELECT * FROM primary_bot_settings WHERE user_id=?',(t['user_id'],)).fetchone())
 from ..core.config import TIMEZONE
 from zoneinfo import ZoneInfo
 today=datetime.now(ZoneInfo(TIMEZONE)).replace(hour=0,minute=0,second=0,microsecond=0).astimezone(timezone.utc).isoformat(timespec='seconds')
 daily=c.execute('SELECT COALESCE(SUM(total_tokens),0) FROM usage_log WHERE user_id=? AND kind=\'owned_task\' AND created_at>=?',(t['user_id'],today)).fetchone()[0]
 daily += c.execute('SELECT COUNT(*)*2048 FROM owned_calls WHERE user_id=? AND usage_unknown=1 AND created_at>=?',(t['user_id'],today)).fetchone()[0]
 if daily>=settings['daily_token_limit']:raise ValueError('主动任务今日额度已用完')
 cid=uuid.uuid4().hex
 c.execute('INSERT INTO owned_calls(id,task_id,user_id,bot_id,step_id,created_at) VALUES (?,?,?,?,?,?)',(cid,t['id'],t['user_id'],step['bot_id'],step['id'],now_iso()))
 c.execute('UPDATE owned_tasks SET chain_calls=chain_calls+1 WHERE id=?',(t['id'],));return cid

def record_call(c,cid,usage,seconds):
 r=row(c.execute('SELECT * FROM owned_calls WHERE id=?',(cid,)).fetchone())
 if not r or r['usage_logged']:return
 known=usage is not None and 'total_tokens' in usage and 'completion_tokens' in usage
 u={k:max(0,int((usage or {}).get(k,0) or 0)) for k in ('prompt_tokens','completion_tokens','total_tokens')}
 c.execute('UPDATE owned_calls SET usage_json=?,usage_unknown=?,usage_logged=1 WHERE id=?',(json.dumps(u),int(not known),cid))
 c.execute('INSERT INTO usage_log(user_id,bot_id,kind,prompt_tokens,completion_tokens,total_tokens,created_at) VALUES (?,?,\'owned_task\',?,?,?,?)',(r['user_id'],r['bot_id'],u['prompt_tokens'],u['completion_tokens'],u['total_tokens'],r['created_at']))
 c.execute('UPDATE owned_tasks SET used_tokens=used_tokens+?,reserved_tokens=reserved_tokens+?,chain_output=chain_output+?,chain_seconds=chain_seconds+? WHERE id=?',(u['total_tokens'],0 if known else 2048,u['completion_tokens'] if known else 2048,seconds,r['task_id']))
def count_tool(c,step):
 t=live(c,step)
 if not t or t['chain_tools']>=8:raise ValueError('工具调用达到上限或执行已停止')
 c.execute('UPDATE owned_tasks SET chain_tools=chain_tools+1 WHERE id=?',(t['id'],))
def pending_delivery(c):
 return [r[0] for r in c.execute("SELECT s.id FROM owned_steps s JOIN owned_tasks t ON t.id=s.task_id WHERE s.delivered_at IS NULL AND s.result_json IS NOT NULL AND s.status NOT IN ('running','retry_wait','cancelled') AND s.kind='owner' AND t.owner_bot_id IS NOT NULL AND s.version=t.version")]
def delivery_item(c,sid):
 return row(c.execute("SELECT s.*,t.user_id,t.owner_bot_id,t.goal,t.delivery_generation,t.state AS task_state FROM owned_steps s JOIN owned_tasks t ON t.id=s.task_id WHERE s.id=? AND s.delivered_at IS NULL AND s.version=t.version AND t.owner_bot_id IS NOT NULL",(sid,)).fetchone())
def deliver_message(c,item,text):
 from .conversation_activity_store import generation
 if generation(c,item['user_id'],'private',item['owner_bot_id'])!=item['delivery_generation']:return None
 return c.execute("INSERT INTO messages(user_id,bot_id,role,content,created_at,source_kind,source_id,conversation_generation) VALUES (?,?,'assistant',?,?,'owned_task',?,?)",(item['user_id'],item['owner_bot_id'],text,now_iso(),item['id'],item['delivery_generation'])).lastrowid
def mark_delivered(c,sid,mid):c.execute('UPDATE owned_steps SET delivered_at=?,message_id=? WHERE id=?',(now_iso(),mid,sid))
def update_task(c,tid,fields):
 c.execute('UPDATE owned_tasks SET '+','.join(k+'=?' for k in fields)+' WHERE id=?',(*fields.values(),tid))
def reset_chain(c,tid):update_task(c,tid,dict(chain_calls=0,chain_output=0,chain_tools=0,chain_seconds=0))
def cursor(c,tid):return c.execute('SELECT COALESCE(MAX(id),0) FROM owned_events WHERE task_id=?',(tid,)).fetchone()[0]
def link_schedule(c,tid,rid):
 update_task(c,tid,{'scheduled_run_id':rid})
 c.execute("UPDATE scheduled_task_runs SET state='retry_wait',available_at='9999-01-01T00:00:00+00:00',error_code='owned_active' WHERE id=?",(rid,))
def finish_schedules(c):
 for r in c.execute("SELECT t.*,r.state AS run_state FROM owned_tasks t JOIN scheduled_task_runs r ON r.id=t.scheduled_run_id WHERE r.state='retry_wait' AND r.error_code='owned_active'").fetchall():
  t=dict(r)
  if t['state'] in TERMINAL:
   last=c.execute('SELECT result_json FROM owned_steps WHERE task_id=? AND result_json IS NOT NULL ORDER BY id DESC LIMIT 1',(t['id'],)).fetchone()
   result=json.loads(last[0]) if last else {}
   c.execute('UPDATE scheduled_task_runs SET state=?,finished_at=?,result_text=?,error_code=?,delivered_at=? WHERE id=?',('succeeded' if t['state']=='completed' else 'cancelled' if t['state']=='stopped' else t['state'],now_iso(),result.get('text'),t['blocker_code'],now_iso(),t['scheduled_run_id']))
   from . import scheduled_task_store,scheduled_run_store
   run=scheduled_run_store.get(c,t['scheduled_run_id']);scheduled_task_store.complete_once(c,run,datetime.now(timezone.utc))
def fence_schedules(c):
 for r in c.execute("SELECT t.* FROM owned_tasks t JOIN scheduled_task_runs r ON r.id=t.scheduled_run_id WHERE r.state='cancelled' AND t.state NOT IN ('completed','stopped','failed','interrupted')").fetchall():invalidate(c,dict(r),'stopped','schedule_cancelled')
def schema_version(c):return int(c.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()[0])

def bind_action(c,step,aid):
 t=live(c,step)
 if not t:raise ValueError('任务已停止')
 c.execute('UPDATE pending_actions SET owned_task_id=?,owned_step_id=?,owned_task_version=? WHERE id=? AND user_id=?',(t['id'],step['id'],t['version'],aid,t['user_id']))
def task_action(c,uid,aid):return row(c.execute('SELECT * FROM pending_actions WHERE user_id=? AND id=?',(uid,aid)).fetchone())
def action_current(c,a,check_permission=True):
 t=get(c,a['user_id'],a['owned_task_id'])
 if not t or t['version']!=a['owned_task_version'] or t['state']!='awaiting_approval':return False
 owner=row(c.execute('SELECT allowed_tools FROM bots WHERE id=? AND user_id=?',(t['owner_bot_id'],t['user_id'])).fetchone())
 frozen=json.loads(t['authorization_json'])
 if check_permission and (not owner or a['tool_full_name'] not in json.loads(owner['allowed_tools'] or '[]') or frozen.get(a['tool_full_name'])!=a['tool_def_hash']):return False
 return bool(c.execute('SELECT 1 FROM owned_waits WHERE task_id=? AND action_id=? AND resolved_at IS NULL',(t['id'],a['id'])).fetchone())
def resolve_action(c,a,content=None):
 if not action_current(c,a,check_permission=False) or a['owned_resolution_at']:return False
 # 'done / executing' is a claimed operation with an unknown result, never success.
 if a['status']=='pending' or a['result']=='执行中…':return False
 t=get(c,a['user_id'],a['owned_task_id'])
 c.execute('UPDATE pending_actions SET owned_resolution_at=? WHERE id=?',(now_iso(),a['id']))
 c.execute('UPDATE owned_waits SET resolved_at=? WHERE action_id=?',(now_iso(),a['id']))
 if a['status']=='done':
  update_task(c,t['id'],dict(tainted=1))
  update_task(c,t['id'],dict(state='queued',blocker_code=None))
  enqueue(c,t,{'approved_action_result':content if content is not None else a['result'],'action_id':a['id']},key=f"approval:{a['id']}")
 else:
  update_task(c,t['id'],dict(state='awaiting_user',blocker_code='approval_'+a['status']))
  c.execute("INSERT OR REPLACE INTO owned_waits(task_id,step_id,version,kind,question) VALUES (?,?,?,'await_user',?)",(t['id'],a['owned_step_id'],t['version'],'操作'+a['status']+'，请补充下一步安排'))
 event(c,t,'approval_resolved',{'action_id':a['id']});return True

def unresolved_actions(c):return [dict(r) for r in c.execute("SELECT * FROM pending_actions WHERE owned_task_id IS NOT NULL AND owned_resolution_at IS NULL AND status<>'pending'")]
def previous_action(c,task_id,version,tool_name,payload_hash):
 return row(c.execute("SELECT * FROM pending_actions WHERE owned_task_id=? AND (owned_task_version=? OR status IN ('done','unknown')) AND tool_full_name=? AND payload_hash=? ORDER BY id DESC LIMIT 1",(task_id,version,tool_name,payload_hash)).fetchone())

def expire_actions(c):
 c.execute("UPDATE pending_actions SET status='unknown',result='执行结果未知，请到对应服务核实' WHERE owned_task_id IS NOT NULL AND status='done' AND result='执行中…' AND decided_at<=?",(stamp_after(-300),))
 c.execute("UPDATE pending_actions SET status='expired',result='确认已过期' WHERE owned_task_id IS NOT NULL AND status='pending' AND expires_at<=?",(now_iso(),))

def memory_ids(c,uid,bot):
 from ..services.memory import repository
 from ..agents.delegation_memory import _visible,_renderable
 candidates=repository.query(c,uid,"m.status='active' AND m.sensitivity='normal' AND m.scope IN ('bot','global')",limit=200)
 return [m['id'] for m in candidates if _visible(m,bot) and _renderable(m)][:12]
def task_memories(c,task,bot):
 from ..services.memory import repository
 from ..agents.delegation_memory import _visible,_renderable
 ids=json.loads(task['authorization_json']).get('__memory_ids',[])
 if not ids:return []
 selected=repository.query(c,task['user_id'],'m.id IN ('+','.join('?'*len(ids))+')',tuple(ids),limit=12)
 return [m for m in selected if _visible(m,bot) and _renderable(m)]
def reopen_schedule(c,t):
 rid=t.get('scheduled_run_id')
 if not rid:return
 linked=c.execute('SELECT r.*,s.state AS definition_state FROM scheduled_task_runs r JOIN scheduled_tasks s ON s.id=r.task_id WHERE r.id=?',(rid,)).fetchone()
 if not linked or linked['definition_state'] in ('paused','deleted'):raise ValueError('请先恢复对应排程')
 other=c.execute("SELECT 1 FROM scheduled_task_runs WHERE task_id=? AND id<>? AND state IN ('queued','running','retry_wait')",(linked['task_id'],rid)).fetchone()
 if other:raise ValueError('该周期任务有其他执行，请先处理')
 c.execute("UPDATE scheduled_task_runs SET state='retry_wait',available_at='9999-01-01T00:00:00+00:00',error_code='owned_active',cancel_requested=0,finished_at=NULL WHERE id=?",(rid,))

def consult_permitted(c,step,task):
 if step['kind']!='consult':return True
 owner=row(c.execute('SELECT allowed_tools,delegate_to FROM bots WHERE id=? AND user_id=?',(task['owner_bot_id'],task['user_id'])).fetchone())
 target=row(c.execute('SELECT accept_delegation FROM bots WHERE id=? AND user_id=?',(step['bot_id'],task['user_id'])).fetchone())
 return bool(owner and target and target['accept_delegation'] and 'ask_bot' in json.loads(owner['allowed_tools'] or '[]') and step['bot_id'] in json.loads(owner['delegate_to'] or '[]') and step['bot_id'] in json.loads(task['authorization_json']).get('__delegates',[]))

def checkpoint_action(c,uid,aid,encoded):
 c.execute('UPDATE pending_actions SET owned_result_enc=? WHERE user_id=? AND id=? AND owned_task_id IS NOT NULL',(encoded,uid,aid))


def notify_with_savepoint(c,callback):
 c.execute('SAVEPOINT notification_delivery')
 try:
  callback()
  c.execute('RELEASE notification_delivery')
  return True
 except Exception:
  c.execute('ROLLBACK TO notification_delivery')
  c.execute('RELEASE notification_delivery')
  return False

def latest_state_event(c, task_id, version):
 return row(c.execute('SELECT e.* FROM owned_events e JOIN owned_tasks t ON t.id=e.task_id WHERE e.task_id=? AND e.version=? AND e.kind=t.state ORDER BY e.id DESC LIMIT 1', (task_id,version)).fetchone())


def pending_state_notifications(c):
 return [dict(r) for r in c.execute("""SELECT e.*,t.owner_bot_id,t.goal,t.state,t.delivery_generation FROM owned_events e JOIN owned_tasks t ON t.id=e.task_id
 WHERE e.notified_at IS NULL AND e.version=t.version AND e.kind=t.state AND e.kind IN ('completed','failed','interrupted','awaiting_user','awaiting_approval')
 AND e.id=(SELECT MAX(x.id) FROM owned_events x WHERE x.task_id=e.task_id AND x.version=e.version AND x.kind=e.kind)
 AND NOT EXISTS(SELECT 1 FROM notifications n WHERE n.user_id=e.user_id AND n.dedupe_key='owned-state:' || e.id)
 AND NOT EXISTS(SELECT 1 FROM owned_steps s WHERE s.task_id=t.id AND s.version=t.version AND s.kind='owner' AND s.result_json IS NOT NULL AND s.delivered_at IS NULL AND s.status NOT IN ('running','retry_wait','cancelled'))
 AND NOT EXISTS(SELECT 1 FROM notifications n JOIN owned_steps s ON n.dedupe_key='owned-step:' || s.id WHERE n.user_id=e.user_id AND s.task_id=t.id AND s.version=t.version)
 ORDER BY e.id LIMIT 100""")]


def mark_state_notified(c, event_id, notification_id):
 c.execute('UPDATE owned_events SET notified_at=?,notification_id=? WHERE id=?', (now_iso(),notification_id,event_id))
