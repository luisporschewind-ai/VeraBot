"""Bind ordinary chat approvals to frozen execution, and resume without replay."""
import json
from .. import db
from . import chat_reply_store as store


def current(c,a):
    if not a.get('chat_task_id'):return True
    t=c.execute('SELECT * FROM chat_reply_tasks WHERE user_id=? AND id=?',(a['user_id'],a['chat_task_id'])).fetchone()
    if not t:return False
    t=dict(t)
    from .repository import _bot
    bot=_bot(c.execute('SELECT * FROM bots WHERE user_id=? AND id=?',(a['user_id'],t['bot_id'])).fetchone())
    return bool(bot and a.get('tool_full_name') in store.authorized_bot(t,bot)['allowed_tools'] and t['state']=='awaiting_approval' and t['version']==a['chat_task_version'] and t['wait_id']==f"action:{a['id']}" and store.activity.generation(c,t['user_id'],'private',t['bot_id'])==t['generation'] and c.execute('SELECT COUNT(*) FROM messages WHERE user_id=? AND id IN (?,?)',(t['user_id'],t['input_message_id'],t['output_message_id'])).fetchone()[0]==2)


def preflight(uid,aid):
    with db.tx() as c:
        a=c.execute('SELECT * FROM pending_actions WHERE id=? AND user_id=?',(aid,uid)).fetchone()
        if a and not current(c,dict(a)):raise ValueError('回复已停止、会话已清空或授权已变更')


def _resolve(c,a):
    if not a.get('chat_task_id') or a.get('chat_resolved_at') or a['status']=='pending':return
    if not current(c,a):return
    t=store.get(c,a['user_id'],a['bot_id'],a['chat_task_id'])
    if a['status']=='done' and a.get('result')=='执行中…':return # live confirmation not yet checkpointed
    cp=store.decode_checkpoint(t['checkpoint_json'])
    from ..services.actions import _decrypt
    result=_decrypt(a.get('chat_result_enc'))
    unknown=a['status']=='unknown' or (a['status']=='done' and not result)
    resolution={'error':'操作结果未知，请到对应服务核实','code':'result_unknown'} if unknown else result or {'error':a.get('result') or a['status'],'code':a['status']}
    # Approval executes outside the runtime: restore the same accounting/taint
    # that synchronous MCP dispatch applies before the model sees its result.
    turn=cp.setdefault('turn',{})
    if a.get('chat_result_enc') is not None or unknown:
        turn['mcp_calls']=int(turn.get('mcp_calls',0))+1
    if resolution.get('content') or resolution.get('code')=='mcp_tool_error':
        turn['untrusted_tainted']=True
        server=c.execute('SELECT name,slug FROM mcp_servers WHERE user_id=? AND id=?',(a['user_id'],a.get('server_id'))).fetchone()
        name=(server['name'] or server['slug']) if server else None
        if not name:
            name=next(((trace.get('result') or {}).get('server') for trace in cp.get('traces',[]) if (trace.get('result') or {}).get('action_id')==a['id']),None)
        seen=set(turn.get('mcp_read_servers') or [])
        if name:seen.add(name)
        turn['mcp_read_servers']=sorted(seen)
    from ..agents.runtime import _tool_content
    for trace in cp.get('traces',[]):
        if (trace.get('result') or {}).get('action_id')==a['id']:
            trace['result']=resolution
            for m in cp.get('messages',[]):
                if m.get('tool_call_id')==trace['id']:m['content']=_tool_content(trace['name'],resolution)
    if unknown:cp['unknown_operation']=True
    state='awaiting_user' if unknown else 'queued'
    wait=f"unknown:{a['id']}" if unknown else None
    c.execute('UPDATE chat_reply_tasks SET state=?,phase=?,version=version+1,wait_id=?,checkpoint_json=?,updated_at=? WHERE id=?',(state,state,wait,store.encode_checkpoint(cp),db.now_iso(),t['id']))
    c.execute('UPDATE messages SET message_status=?,content=? WHERE id=? AND user_id=?',(state,cp.get('answer','')+('\n\n操作结果未知，请核实，系统不会自动重放。' if unknown else ''),t['output_message_id'],t['user_id']))
    c.execute('UPDATE pending_actions SET chat_resolved_at=? WHERE id=? AND user_id=?',(db.now_iso(),a['id'],a['user_id']))
    c.execute('UPDATE chat_tool_attempts SET result_enc=?,state=? WHERE task_id=? AND action_id=?',(a.get('chat_result_enc'),'unknown' if unknown else 'completed',t['id'],a['id']))
    fresh=store.get(c,t['user_id'],t['bot_id'],t['id']);store.event(c,fresh,'task_updated',{'task':store.public(c,fresh)})


def resolve(uid,aid):
    with db.tx(immediate=True) as c:
        r=c.execute('SELECT * FROM pending_actions WHERE id=? AND user_id=?',(aid,uid)).fetchone()
        if r:_resolve(c,dict(r))


def reconcile():
    with db.tx(immediate=True) as c:
        c.execute("UPDATE pending_actions SET status='expired',result='确认已过期',decided_at=? WHERE chat_task_id IS NOT NULL AND status='pending' AND expires_at<=?",(db.now_iso(),db.now_iso()))
        # A confirmation claimed >60s ago is uncertain after restart. Never invoke it again.
        from datetime import datetime,timedelta,timezone
        stale=(datetime.now(timezone.utc)-timedelta(seconds=60)).isoformat(timespec='seconds')
        c.execute("UPDATE pending_actions SET status='unknown',result='确认执行结果未知' WHERE chat_task_id IS NOT NULL AND status='done' AND result='执行中…' AND decided_at<?",(stale,))
        for r in c.execute('SELECT * FROM pending_actions WHERE chat_task_id IS NOT NULL AND chat_resolved_at IS NULL').fetchall():_resolve(c,dict(r))
