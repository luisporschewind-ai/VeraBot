"""Consistent account summaries and sparse, monotonic message reads."""
import json
from .database import tx, now_iso


class ActivityError(Exception):
    def __init__(self,status,code,message):
        self.status,self.code,self.message=status,code,message
        super().__init__(message)


def generation(c, uid, kind, cid):
    r=c.execute('SELECT generation FROM conversation_activity WHERE user_id=? AND kind=? AND conversation_id=?',(uid,kind,cid)).fetchone()
    return r[0] if r else 1


def cursor(c,uid):
    return c.execute('SELECT COALESCE(MAX(id),0) FROM conversation_events WHERE user_id=?',(uid,)).fetchone()[0]


def ensure_owned(c,uid,kind,cid):
    table='bots' if kind=='private' else 'chat_groups' if kind=='group' else None
    if not table or not c.execute(f'SELECT 1 FROM {table} WHERE user_id=? AND id=?',(uid,cid)).fetchone():
        raise ActivityError(404,'not_found','会话不存在')


def clear(c,uid,kind,cid):
    c.execute('INSERT OR IGNORE INTO conversation_activity VALUES(?,?,?,1)',(uid,kind,cid))
    c.execute('UPDATE conversation_activity SET generation=generation+1 WHERE user_id=? AND kind=? AND conversation_id=?',(uid,kind,cid))
    c.execute('DELETE FROM message_read_receipts WHERE user_id=? AND kind=? AND conversation_id=?',(uid,kind,cid))
    c.execute('DELETE FROM message_publications WHERE user_id=? AND kind=? AND conversation_id=?',(uid,kind,cid))
    if kind=='private':
        c.execute("UPDATE chat_reply_tasks SET state='stopped',phase='stopped',version=version+1,lease_token=NULL,updated_at=? WHERE user_id=? AND bot_id=? AND state NOT IN ('completed','failed','stopped','interrupted')",(now_iso(),uid,cid))
    c.execute("INSERT INTO conversation_events(user_id,kind,conversation_id,generation,event,created_at) VALUES(?,?,?,?,'conversation_cleared',?)",(uid,kind,cid,generation(c,uid,kind,cid),now_iso()))


def summary(c,uid,kind,cid):
    gen=generation(c,uid,kind,cid)
    unread=[dict(r) for r in c.execute('''SELECT p.message_id,p.publication_revision FROM message_publications p
 LEFT JOIN message_read_receipts r USING(user_id,kind,conversation_id,generation,message_id)
 WHERE p.user_id=? AND p.kind=? AND p.conversation_id=? AND p.generation=?
 AND p.publication_revision>COALESCE(r.publication_revision,0) ORDER BY p.message_id''',(uid,kind,cid,gen))]
    if kind=='private':
        # superseded_at: failed/interrupted work followed by a later completed reply or task (v33 triggers).
        work=[dict(r) for r in c.execute("SELECT id,state,phase,version,wait_id,'chat' AS source FROM chat_reply_tasks WHERE user_id=? AND bot_id=? AND generation=? AND state NOT IN ('completed','stopped') AND superseded_at IS NULL ORDER BY id",(uid,cid,gen))]
        work += [dict(r) for r in c.execute("SELECT id,state,state AS phase,version,NULL AS wait_id,'owned' AS source FROM owned_tasks WHERE user_id=? AND owner_bot_id=? AND delivery_generation=? AND state NOT IN ('completed','stopped') AND superseded_at IS NULL ORDER BY id",(uid,cid,gen))]
        latest=c.execute("SELECT id,content,created_at FROM messages WHERE user_id=? AND bot_id=? AND conversation_generation=? AND message_status NOT IN ('queued','running') ORDER BY id DESC LIMIT 1",(uid,cid,gen)).fetchone()
    else:
        work=[dict(r) for r in c.execute("SELECT id,state,state AS phase,version,NULL AS wait_id,'group' AS source,owner_member_id FROM chat_group_tasks WHERE user_id=? AND group_id=? AND state NOT IN ('completed','stopped') ORDER BY id",(uid,cid))]
        latest=c.execute("SELECT id,content,created_at FROM chat_group_messages WHERE user_id=? AND group_id=? AND status NOT IN ('queued','streaming') ORDER BY id DESC LIMIT 1",(uid,cid)).fetchone()
    priority={'awaiting_user':0,'awaiting_approval':0,'running':1,'queued':3,'retry_wait':3,'failed':4,'interrupted':4}
    work.sort(key=lambda r:(priority.get(r['state'],2),0 if r['source']=='chat' else 1,r['id']))
    selected=work[0] if work else None
    revision=c.execute('SELECT COALESCE(MAX(id),0) FROM conversation_events WHERE user_id=? AND kind=? AND conversation_id=?',(uid,kind,cid)).fetchone()[0]
    return dict(kind=kind,conversation_id=cid,generation=gen,revision=revision,state=selected['state'] if selected else 'idle',phase=selected['phase'] if selected else 'idle',unread_count=len(unread),pending_count=sum(r['state'] in ('awaiting_user','awaiting_approval') for r in work),unread_messages=unread,work_items=work,latest_message=dict(latest) if latest else None)


def snapshot(uid):
    with tx() as c:
        c.execute('BEGIN')
        conversations=[summary(c,uid,'private',r[0]) for r in c.execute('SELECT id FROM bots WHERE user_id=? ORDER BY id',(uid,))]
        conversations += [summary(c,uid,'group',r[0]) for r in c.execute('SELECT id FROM chat_groups WHERE user_id=? ORDER BY id',(uid,))]
        return {'cursor':cursor(c,uid),'conversations':conversations}


def read(uid,kind,cid,gen,messages):
    with tx(immediate=True) as c:
        ensure_owned(c,uid,kind,cid)
        if generation(c,uid,kind,cid)!=gen:raise ActivityError(409,'generation_changed','会话已清空，请重新同步')
        for item in messages:
            pub=c.execute('SELECT publication_revision FROM message_publications WHERE user_id=? AND kind=? AND conversation_id=? AND generation=? AND message_id=?',(uid,kind,cid,gen,item['message_id'])).fetchone()
            if not pub or item['publication_revision']>pub[0]:raise ActivityError(409,'publication_changed','消息版本尚未发布或已删除')
            c.execute('''INSERT INTO message_read_receipts VALUES(?,?,?,?,?,?) ON CONFLICT(user_id,kind,conversation_id,generation,message_id)
 DO UPDATE SET publication_revision=MAX(publication_revision,excluded.publication_revision)''',(uid,kind,cid,gen,item['message_id'],item['publication_revision']))
        c.execute("INSERT INTO conversation_events(user_id,kind,conversation_id,generation,event,created_at) VALUES(?,?,?,?,'messages_read',?)",(uid,kind,cid,gen,now_iso()))
        return {'cursor':cursor(c,uid),'conversation':summary(c,uid,kind,cid)}


def events(uid,after):
    with tx() as c:
        c.execute('BEGIN')
        current=cursor(c,uid)
        if after>current:raise ActivityError(409,'cursor_invalid','同步游标无效，请重新获取快照')
        return [dict(id=r['id'],event=r['event'],data={'kind':r['kind'],'conversation_id':r['conversation_id'],'generation':r['generation'],'conversation':summary(c,uid,r['kind'],r['conversation_id']) if c.execute('SELECT 1 FROM '+('bots' if r['kind']=='private' else 'chat_groups')+' WHERE user_id=? AND id=?',(uid,r['conversation_id'])).fetchone() else None}) for r in c.execute('SELECT * FROM conversation_events WHERE user_id=? AND id>? ORDER BY id LIMIT 100',(uid,after))]


def remove(c,uid,kind,cid):
    gen=generation(c,uid,kind,cid)
    c.execute('DELETE FROM message_publications WHERE user_id=? AND kind=? AND conversation_id=?',(uid,kind,cid))
    c.execute('DELETE FROM message_read_receipts WHERE user_id=? AND kind=? AND conversation_id=?',(uid,kind,cid))
    c.execute('DELETE FROM conversation_activity WHERE user_id=? AND kind=? AND conversation_id=?',(uid,kind,cid))
    c.execute("INSERT INTO conversation_events(user_id,kind,conversation_id,generation,event,created_at) VALUES(?,?,?,?,'conversation_deleted',?)",(uid,kind,cid,gen,now_iso()))
