"""Atomic durable receipts, execution leases and frozen tool checkpoints."""
import hashlib
import json
import os
import uuid
from datetime import datetime,timedelta,timezone
from .database import tx,now_iso
from . import conversation_activity_store as activity
from ..core.trace_slim import slim_trace,slim_traces

TERMINAL={'completed','failed','stopped','interrupted'}
class ChatTaskError(activity.ActivityError):pass

def digest(payload):return hashlib.sha256(json.dumps(payload,sort_keys=True,ensure_ascii=False,separators=(',',':')).encode()).hexdigest()

def get(c,uid,bid,tid):
    r=c.execute('SELECT * FROM chat_reply_tasks WHERE id=? AND user_id=? AND bot_id=?',(tid,uid,bid)).fetchone()
    if not r:raise ChatTaskError(404,'not_found','回复任务不存在')
    return dict(r)

def public(c,t):
    m=c.execute('SELECT * FROM messages WHERE id=? AND user_id=?',(t['output_message_id'],t['user_id'])).fetchone()
    p=c.execute("SELECT publication_revision FROM message_publications WHERE user_id=? AND kind='private' AND conversation_id=? AND generation=? AND message_id=?",(t['user_id'],t['bot_id'],t['generation'],t['output_message_id'])).fetchone()
    return {k:t[k] for k in ('id','bot_id','generation','client_request_id','state','phase','version','wait_id','error_code','created_at','updated_at')} | dict(user_message_id=t['input_message_id'],assistant_message_id=t['output_message_id'],content=m['content'] if m else '',traces=json.loads(m['traces'] or '[]') if m else [],message_status=m['message_status'] if m else 'deleted',publication_revision=p[0] if p else 0)

def receipt(c,uid,bid,key):
    r=c.execute('SELECT * FROM chat_input_receipts WHERE user_id=? AND bot_id=? AND request_id=?',(uid,bid,key)).fetchone()
    return dict(r) if r else None

def accept(c,uid,bid,payload):
    key=payload['client_request_id'];h=digest(payload)
    old=receipt(c,uid,bid,key)
    if old:
        if old['payload_hash']!=h:raise ChatTaskError(409,'request_conflict','请求 ID 已用于不同消息')
        return json.loads(old['response_json']),False
    activity.ensure_owned(c,uid,'private',bid)
    if c.execute("SELECT 1 FROM chat_legacy_sessions WHERE user_id=? AND bot_id=?",(uid,bid)).fetchone():raise ChatTaskError(409,"chat_busy","旧版对话仍在运行，请稍后重试同一请求")
    gen=activity.generation(c,uid,'private',bid)
    if payload['expected_generation']!=gen:raise ChatTaskError(409,'generation_changed','会话已清空，请重新同步')
    from ..services.attachments import repo as attachments
    from . import attachment_store
    # Files were checked before locking; enforce ownership/status again under the receipt transaction.
    for aid in payload.get('attachment_ids',[]):
        a=attachment_store.get(c,uid,aid)
        if not a or a['status']!='pending' or (a['bot_id'] is not None and a['bot_id']!=bid):raise ChatTaskError(409,'attachment_changed','附件状态已变更')
    now=now_iso()
    inp=c.execute("INSERT INTO messages(user_id,bot_id,role,content,created_at,conversation_generation) VALUES (?,?,'user',?,?,?)",(uid,bid,payload['message'].strip(),now,gen)).lastrowid
    out=c.execute("INSERT INTO messages(user_id,bot_id,role,content,created_at,message_status,conversation_generation) VALUES (?,?,'assistant','',?,'queued',?)",(uid,bid,now,gen)).lastrowid
    for aid in payload.get('attachment_ids',[]):attachment_store.attach(c,uid,aid,inp,bid)
    tid=c.execute('INSERT INTO chat_reply_tasks(user_id,bot_id,generation,client_request_id,payload_hash,input_message_id,output_message_id,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?)',(uid,bid,gen,key,h,inp,out,now,now)).lastrowid
    bot=c.execute("SELECT allowed_tools,delegate_to,memory_access FROM bots WHERE user_id=? AND id=?",(uid,bid)).fetchone()
    authorization={"allowed_tools":json.loads(bot["allowed_tools"] or "[]"),"delegate_to":json.loads(bot["delegate_to"] or "[]"),"memory_access":bot["memory_access"] or "none"}
    c.execute("UPDATE chat_reply_tasks SET authorization_json=? WHERE id=?",(json.dumps(authorization),tid))
    t=get(c,uid,bid,tid);event(c,t,'accepted',{'task':public(c,t)})
    response={'task':public(c,t),'user_message_id':inp,'assistant_message_id':out,'generation':gen,'cursor':activity.cursor(c,uid)}
    c.execute('INSERT INTO chat_input_receipts VALUES(?,?,?,?,?)',(uid,bid,key,h,json.dumps(response,ensure_ascii=False)))
    return response,True

def event(c,t,kind,data):
    if kind=='tool_result':data=slim_trace(data)
    c.execute('INSERT INTO chat_reply_events(user_id,bot_id,task_id,generation,version,event,payload_json,created_at) VALUES(?,?,?,?,?,?,?,?)',(t['user_id'],t['bot_id'],t['id'],t['generation'],t['version'],kind,json.dumps(data,ensure_ascii=False),now_iso()))

def live(c,t):
    r=c.execute("SELECT * FROM chat_reply_tasks WHERE id=? AND user_id=? AND bot_id=? AND generation=? AND version=? AND lease_token=? AND state='running' AND lease_expires_at>?",(t['id'],t['user_id'],t['bot_id'],t['generation'],t['version'],t['lease_token'],now_iso())).fetchone()
    return bool(r and activity.generation(c,t['user_id'],'private',t['bot_id'])==t['generation'] and c.execute('SELECT COUNT(*) FROM messages WHERE user_id=? AND bot_id=? AND id IN (?,?)',(t['user_id'],t['bot_id'],t['input_message_id'],t['output_message_id'])).fetchone()[0]==2)

def claim_next(c,worker_id):
    global_limit=max(1,int(os.getenv('VERABOT_CHAT_CONCURRENCY','4')))
    user_limit=max(1,int(os.getenv('VERABOT_CHAT_USER_CONCURRENCY','2')))
    if c.execute("SELECT COUNT(*) FROM chat_reply_tasks WHERE state='running'").fetchone()[0]>=global_limit:return None
    for r in c.execute("SELECT * FROM chat_reply_tasks WHERE state='queued' ORDER BY id").fetchall():
        t=dict(r)
        if activity.generation(c,t['user_id'],'private',t['bot_id'])!=t['generation']:continue
        if c.execute("SELECT COUNT(*) FROM chat_reply_tasks WHERE user_id=? AND state='running'",(t['user_id'],)).fetchone()[0]>=user_limit:continue
        if c.execute("SELECT 1 FROM chat_reply_tasks WHERE user_id=? AND bot_id=? AND state='running'",(t['user_id'],t['bot_id'])).fetchone():continue
        token=f'{worker_id}:{uuid.uuid4().hex}'
        c.execute("UPDATE chat_reply_tasks SET state='running',phase='recalling',lease_token=?,lease_expires_at=?,updated_at=? WHERE id=? AND state='queued'",(token,(datetime.now(timezone.utc)+timedelta(seconds=30)).isoformat(timespec='seconds'),now_iso(),t['id']))
        c.execute("UPDATE messages SET message_status='running' WHERE id=?",(t['output_message_id'],))
        t=get(c,t['user_id'],t['bot_id'],t['id']);event(c,t,'task_updated',{'task':public(c,t)})
        return t
    return None

def heartbeat(c,t):
    if not live(c,t):return False
    c.execute('UPDATE chat_reply_tasks SET lease_expires_at=? WHERE id=?',((datetime.now(timezone.utc)+timedelta(seconds=30)).isoformat(timespec='seconds'),t['id']))
    return True

def save_partial(c,t,text,traces):
    if not live(c,t):return False
    traces=slim_traces(traces)
    c.execute('UPDATE messages SET content=?,traces=? WHERE id=? AND user_id=?',(text,json.dumps(traces,ensure_ascii=False),t['output_message_id'],t['user_id']))
    event(c,t,'message_updated',{'message_id':t['output_message_id'],'content':text,'traces':traces,'message_status':'running','publication_revision':0})
    return True

def finish(c,t,state,text,traces,error_code=None,wait_id=None):
    if not live(c,t):return False
    traces=slim_traces(traces)
    c.execute('UPDATE messages SET content=?,traces=?,message_status=? WHERE id=? AND user_id=?',(text,json.dumps(traces,ensure_ascii=False),state,t['output_message_id'],t['user_id']))
    c.execute('UPDATE chat_reply_tasks SET state=?,phase=?,wait_id=?,error_code=?,lease_token=NULL,lease_expires_at=NULL,updated_at=? WHERE id=?',(state,state,wait_id,error_code,now_iso(),t['id']))
    fresh=get(c,t['user_id'],t['bot_id'],t['id']);event(c,fresh,'task_updated',{'task':public(c,fresh)})
    _notify_published_reply(c,fresh,state,text)
    return True

def recover(c):
    for r in c.execute("SELECT * FROM chat_reply_tasks WHERE state='running' AND lease_expires_at<=?",(now_iso(),)).fetchall():
        t=dict(r)
        c.execute("UPDATE chat_reply_tasks SET state='interrupted',phase='interrupted',version=version+1,lease_token=NULL,error_code='worker_interrupted',updated_at=? WHERE id=?",(now_iso(),t['id']))
        c.execute("UPDATE messages SET content=content||'\n\n回复因服务中断而停止，请核实已执行的操作。',message_status='interrupted' WHERE id=? AND user_id=?",(t['output_message_id'],t['user_id']))
        fresh=get(c,t['user_id'],t['bot_id'],t['id'])
        event(c,fresh,'task_updated',{'reason':'worker_interrupted'})
        text=c.execute('SELECT content FROM messages WHERE id=? AND user_id=?',(t['output_message_id'],t['user_id'])).fetchone()
        _notify_published_reply(c,fresh,'interrupted',text['content'] if text else '')
    c.execute("UPDATE chat_tool_attempts SET state='unknown' WHERE state='running' AND task_id IN (SELECT id FROM chat_reply_tasks WHERE state='interrupted')")


def _notify_published_reply(c,t,state,text):
    if state not in ('completed','awaiting_user','awaiting_approval','failed','interrupted'):
        return
    c.execute('SAVEPOINT chat_reply_notify')
    try:
        from ..services.notify.dispatcher import notify
        name=c.execute('SELECT name FROM bots WHERE id=? AND user_id=?',(t['bot_id'],t['user_id'])).fetchone()
        label=name['name'] if name else '助手'
        title={'completed':f'「{label}」有新消息','awaiting_user':f'「{label}」需要你补充','awaiting_approval':f'「{label}」需要你确认','failed':f'「{label}」回复失败','interrupted':f'「{label}」回复中断'}[state]
        notify(t['user_id'],category='bot_message',title=title,body=(text or '')[:160] or None,bot_id=t['bot_id'],message_id=t['output_message_id'],
               link=f"bot/{t['bot_id']}/chat?message={t['output_message_id']}",thread_id=f"bot:{t['bot_id']}",
               dedupe_key=f"chat-reply:{t['id']}:{t['version']}:{state}",source_kind='chat_reply',source_id=str(t['id']),source_state=state,conn=c)
        c.execute('RELEASE chat_reply_notify')
    except Exception:
        c.execute('ROLLBACK TO chat_reply_notify')
        c.execute('RELEASE chat_reply_notify')
        import logging
        logging.getLogger(__name__).warning('chat reply notification failed task=%s',t.get('id'))

def start_tool(c,t,tc):
    if not live(c,t):raise ChatTaskError(409,'task_changed','回复已停止')
    from ..services.actions import _encrypt,_decrypt
    old=c.execute('SELECT * FROM chat_tool_attempts WHERE task_id=? AND call_id=?',(t['id'],tc['id'])).fetchone()
    if old:
        frozen=_decrypt(old['arguments_enc'])
        if old['tool']!=tc['name'] or frozen!={'arguments':tc['arguments']}:raise ChatTaskError(409,'tool_call_conflict','工具调用 ID 参数冲突')
        if old['state']=='completed':return _decrypt(old['result_enc'])
        raise ChatTaskError(409,'operation_unknown','工具结果尚未确定，不能重放')
    c.execute("INSERT INTO chat_tool_attempts(task_id,call_id,tool,arguments_enc,state) VALUES(?,?,?,?,'running')",(t['id'],tc['id'],tc['name'],_encrypt({'arguments':tc['arguments']})))
    return None

def complete_tool(c,t,tc,result):
    if not live(c,t):return False
    from ..services.actions import _encrypt
    c.execute("UPDATE chat_tool_attempts SET state='completed',result_enc=?,action_id=? WHERE task_id=? AND call_id=?",(_encrypt(result),result.get('action_id'),t['id'],tc['id']))
    return True

def control(c,uid,bid,tid,payload,answer=False):
    t=get(c,uid,bid,tid);key=('answer:' if answer else 'stop:')+payload.get('client_request_id',payload.get('control_request_id',''));h=digest(payload)
    old=c.execute('SELECT * FROM chat_control_receipts WHERE user_id=? AND task_id=? AND request_id=?',(uid,tid,key)).fetchone()
    if old:
        if old['payload_hash']!=h:raise ChatTaskError(409,'request_conflict','控制请求 ID 冲突')
        return json.loads(old['response_json'])
    if t['version']!=payload['expected_version'] or activity.generation(c,uid,'private',bid)!=t['generation']:raise ChatTaskError(409,'task_changed','任务版本已更新')
    answer_message_id=None
    if answer:
        if t['state']!='awaiting_user' or not t['wait_id'] or t['wait_id']!=payload['wait_id']:raise ChatTaskError(409,'wait_changed','等待项已更新，请重新同步')
        checkpoint=decode_checkpoint(t['checkpoint_json'])
        if checkpoint.get('unknown_operation'):raise ChatTaskError(409,'operation_unknown','请核实外部结果，不能重放未知操作')
        checkpoint.setdefault('messages',[]).append({'role':'user','content':payload['message']})
        answer_message_id=c.execute("INSERT INTO messages(user_id,bot_id,role,content,created_at,conversation_generation) VALUES(?,?,'user',?,?,?)",(uid,bid,payload['message'],now_iso(),t['generation'])).lastrowid
        c.execute("UPDATE chat_reply_tasks SET state='queued',phase='queued',version=version+1,wait_id=NULL,checkpoint_json=?,updated_at=? WHERE id=?",(encode_checkpoint(checkpoint),now_iso(),tid))
        c.execute("UPDATE messages SET message_status='queued' WHERE id=?",(t['output_message_id'],))
    else:
        if t['state'] not in TERMINAL:
            c.execute("UPDATE chat_reply_tasks SET state='stopped',phase='stopped',version=version+1,lease_token=NULL,updated_at=? WHERE id=?",(now_iso(),tid))
            c.execute("UPDATE messages SET content=CASE WHEN content='' THEN '回复已停止' ELSE content||'\n\n回复已停止' END,message_status='stopped' WHERE id=? AND user_id=?",(t['output_message_id'],uid))
    fresh=get(c,uid,bid,tid);response={'task':public(c,fresh),'generation':fresh['generation'],'cursor':activity.cursor(c,uid)}
    if answer:response['answer_message_id']=answer_message_id
    event(c,fresh,'task_updated',{'task':response['task']})
    c.execute('INSERT INTO chat_control_receipts VALUES(?,?,?,?,?)',(uid,tid,key,h,json.dumps(response,ensure_ascii=False)))
    return response

def execution(uid,bid):
    with tx() as c:
        c.execute('BEGIN');activity.ensure_owned(c,uid,'private',bid);gen=activity.generation(c,uid,'private',bid)
        tasks=[public(c,dict(r)) for r in c.execute('SELECT * FROM chat_reply_tasks WHERE user_id=? AND bot_id=? AND generation=? ORDER BY id',(uid,bid,gen))]
        return {'generation':gen,'cursor':activity.cursor(c,uid),'event_cursor':c.execute('SELECT COALESCE(MAX(id),0) FROM chat_reply_events WHERE user_id=? AND bot_id=?',(uid,bid)).fetchone()[0],'tasks':tasks}

def events(uid,bid,after):
    with tx() as c:
        activity.ensure_owned(c,uid,'private',bid)
        current=c.execute('SELECT COALESCE(MAX(id),0) FROM chat_reply_events WHERE user_id=? AND bot_id=?',(uid,bid)).fetchone()[0]
        if after>current:raise ChatTaskError(409,'cursor_invalid','请重新同步会话')
        return [{'id':r['id'],'event':r['event'],'data':json.loads(r['payload_json'])|{'task_id':r['task_id'],'generation':r['generation'],'version':r['version']}} for r in c.execute('SELECT * FROM chat_reply_events WHERE user_id=? AND bot_id=? AND id>? ORDER BY id LIMIT 100',(uid,bid,after))]


def encode_checkpoint(data):
    from ..services.actions import _encrypt
    return _encrypt(data).decode()

def decode_checkpoint(data):
    from ..services.actions import _decrypt
    if not data:return {}
    result=_decrypt(data)
    if result is None:raise ChatTaskError(409,'checkpoint_unavailable','执行检查点无法读取')
    return result


def busy(c,uid,bid):
    return c.execute("SELECT 1 FROM chat_reply_tasks WHERE user_id=? AND bot_id=? AND state NOT IN ('completed','failed','stopped','interrupted')",(uid,bid)).fetchone() is not None

def history_rows(c,t):
    rows=c.execute("SELECT id,role,content,traces,source_kind,source_id FROM messages WHERE user_id=? AND bot_id=? AND conversation_generation=? AND id<? AND message_status='completed' ORDER BY id DESC LIMIT 30",(t['user_id'],t['bot_id'],t['generation'],t['input_message_id'])).fetchall()
    return [dict(r) for r in reversed(rows)]

def save_checkpoint(c,t,data):
    if not live(c,t):return False
    c.execute('UPDATE chat_reply_tasks SET checkpoint_json=? WHERE id=?',(encode_checkpoint(data),t['id']))
    return True

def set_memory_ids(c,t,ids):
    c.execute('UPDATE messages SET memory_ids=? WHERE id=? AND user_id=?',(json.dumps(ids),t['output_message_id'],t['user_id']))

def postprocess_allowed(c,t):
    return activity.generation(c,t['user_id'],'private',t['bot_id'])==t['generation'] and c.execute('SELECT 1 FROM messages WHERE id=? AND user_id=?',(t['output_message_id'],t['user_id'])).fetchone() is not None

def phase(c,t,value):
    c.execute('UPDATE chat_reply_tasks SET phase=?,updated_at=? WHERE id=? AND user_id=?',(value,now_iso(),t['id'],t['user_id']))

def input_content(c,t):
    return c.execute('SELECT content FROM messages WHERE id=? AND user_id=?',(t['input_message_id'],t['user_id'])).fetchone()['content']

def bind_action(c,t,aid):
    if not live(c,t):
        c.execute("UPDATE pending_actions SET status='cancelled',result='回复已停止' WHERE id=? AND user_id=?",(aid,t['user_id']))
        return False
    c.execute('UPDATE pending_actions SET chat_task_id=?,chat_task_version=? WHERE id=? AND user_id=?',(t['id'],t['version'],aid,t['user_id']))
    return True

def checkpoint_action(c,uid,aid,result):
    c.execute('UPDATE pending_actions SET chat_result_enc=? WHERE id=? AND user_id=?',(result,aid,uid))

def bind_wait_action(c,t,aid):
    c.execute('UPDATE pending_actions SET chat_task_id=?,chat_task_version=? WHERE id=? AND user_id=?',(t['id'],t['version'],aid,t['user_id']))


def postprocess(c,t,rec_ids,memory_tools):
    if rec_ids:
        marks=','.join('?' for _ in rec_ids)
        c.execute(f'UPDATE memories SET use_count=use_count+1,last_used_at=? WHERE user_id=? AND id IN ({marks})',(now_iso(),t['user_id'],*rec_ids))
    if memory_tools:
        from . import memory_job_store
        memory_job_store.enqueue(c,user_id=t['user_id'],bot_id=t['bot_id'],kind='summarize',after_message_id=t['output_message_id'])


def model_call(c,t,call_id,state):
    if state=='running':
        if not live(c,t):raise ChatTaskError(409,'task_changed','回复已停止')
        c.execute('INSERT INTO chat_model_calls(id,task_id,user_id,version,state,created_at) VALUES(?,?,?,?,?,?)',(call_id,t['id'],t['user_id'],t['version'],state,now_iso()))
    else:c.execute('UPDATE chat_model_calls SET state=? WHERE id=? AND user_id=?',(state,call_id,t['user_id']))

def charge_call(c,t,call_id,usage):
    found=c.execute('SELECT usage_logged FROM chat_model_calls WHERE id=? AND user_id=?',(call_id,t['user_id'])).fetchone()
    if not found or found[0]:return
    c.execute('UPDATE chat_model_calls SET usage_json=?,usage_logged=1 WHERE id=?',(json.dumps(usage),call_id))
    c.execute('INSERT INTO usage_log(user_id,bot_id,kind,prompt_tokens,completion_tokens,total_tokens,created_at) VALUES(?,?,"chat",?,?,?,?)',(t['user_id'],t['bot_id'],int(usage.get('prompt_tokens') or 0),int(usage.get('completion_tokens') or 0),int(usage.get('total_tokens') or 0),now_iso()))


def postprocess_safely(c,callback):
    c.execute('SAVEPOINT chat_postprocessing')
    try:
        result=callback()
        c.execute('RELEASE chat_postprocessing')
        return True,result
    except Exception:
        c.execute('ROLLBACK TO chat_postprocessing')
        c.execute('RELEASE chat_postprocessing')
        return False,None


def cancel_bot_actions(c,uid,bid):
    c.execute("UPDATE pending_actions SET status='cancelled',result='Bot 已删除',decided_at=? WHERE user_id=? AND bot_id=? AND chat_task_id IS NOT NULL AND status='pending'",(now_iso(),uid,bid))


def reserve_legacy(c,uid,bid):
    if busy(c,uid,bid) or c.execute('SELECT 1 FROM chat_legacy_sessions WHERE user_id=? AND bot_id=?',(uid,bid)).fetchone():raise ChatTaskError(409,'chat_busy','该会话已有回复在运行')
    token=uuid.uuid4().hex
    c.execute('INSERT INTO chat_legacy_sessions VALUES(?,?,?)',(uid,bid,token))
    return token

def release_legacy(c,uid,bid,token):
    c.execute('DELETE FROM chat_legacy_sessions WHERE user_id=? AND bot_id=? AND token=?',(uid,bid,token))

def recover_legacy(c):
    # Existing single API process deployment constraint: startup means old HTTP streams are gone.
    c.execute('DELETE FROM chat_legacy_sessions')


def authorized_bot(t,bot):
    frozen=json.loads(t.get('authorization_json') or '{}')
    result=dict(bot)
    for name in ('allowed_tools','delegate_to'):
        allowed=set(frozen.get(name) or [])
        result[name]=[value for value in bot.get(name,[]) if value in allowed]
    accesses=['none','bot','bot_and_global']
    current=bot.get('memory_access') or 'none';accepted=frozen.get('memory_access') or 'none'
    result['memory_access']=accesses[min(accesses.index(current),accesses.index(accepted))]
    return result
