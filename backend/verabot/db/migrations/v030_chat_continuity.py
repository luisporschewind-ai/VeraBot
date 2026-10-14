"""Durable private replies and per-message publication/read revisions."""
import sqlite3
from ._util import _add_column

SCHEMA = '''
CREATE TABLE IF NOT EXISTS conversation_activity (
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE, kind TEXT NOT NULL,
 conversation_id INTEGER NOT NULL, generation INTEGER NOT NULL DEFAULT 1,
 PRIMARY KEY(user_id,kind,conversation_id));
CREATE TABLE IF NOT EXISTS message_publications (
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,kind TEXT NOT NULL,
 conversation_id INTEGER NOT NULL,generation INTEGER NOT NULL,message_id INTEGER NOT NULL,
 publication_revision INTEGER NOT NULL DEFAULT 1,
 PRIMARY KEY(user_id,kind,conversation_id,generation,message_id));
CREATE TABLE IF NOT EXISTS message_read_receipts (
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,kind TEXT NOT NULL,
 conversation_id INTEGER NOT NULL,generation INTEGER NOT NULL,message_id INTEGER NOT NULL,
 publication_revision INTEGER NOT NULL,
 PRIMARY KEY(user_id,kind,conversation_id,generation,message_id));
CREATE TABLE IF NOT EXISTS conversation_events (
 id INTEGER PRIMARY KEY AUTOINCREMENT,user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 kind TEXT NOT NULL,conversation_id INTEGER NOT NULL,generation INTEGER NOT NULL,
 event TEXT NOT NULL,payload_json TEXT NOT NULL DEFAULT '{}',created_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS chat_legacy_sessions (
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 bot_id INTEGER NOT NULL REFERENCES bots(id) ON DELETE CASCADE,token TEXT NOT NULL,
 PRIMARY KEY(user_id,bot_id));
CREATE TABLE IF NOT EXISTS chat_reply_tasks (
 id INTEGER PRIMARY KEY AUTOINCREMENT,user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 bot_id INTEGER NOT NULL REFERENCES bots(id) ON DELETE CASCADE,generation INTEGER NOT NULL,
 client_request_id TEXT NOT NULL,payload_hash TEXT NOT NULL,input_message_id INTEGER NOT NULL,
 output_message_id INTEGER NOT NULL,state TEXT NOT NULL DEFAULT 'queued',phase TEXT NOT NULL DEFAULT 'queued',
 version INTEGER NOT NULL DEFAULT 1,lease_token TEXT,lease_expires_at TEXT,
 checkpoint_json TEXT,wait_id TEXT,error_code TEXT,created_at TEXT NOT NULL,updated_at TEXT NOT NULL,
 UNIQUE(user_id,bot_id,client_request_id));
CREATE UNIQUE INDEX IF NOT EXISTS chat_one_running ON chat_reply_tasks(user_id,bot_id) WHERE state='running';
CREATE TABLE IF NOT EXISTS chat_reply_events (
 id INTEGER PRIMARY KEY AUTOINCREMENT,user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 bot_id INTEGER NOT NULL,task_id INTEGER NOT NULL REFERENCES chat_reply_tasks(id) ON DELETE CASCADE,
 generation INTEGER NOT NULL,version INTEGER NOT NULL,event TEXT NOT NULL,payload_json TEXT NOT NULL,created_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS chat_input_receipts (
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,bot_id INTEGER NOT NULL,request_id TEXT NOT NULL,
 payload_hash TEXT NOT NULL,response_json TEXT NOT NULL,PRIMARY KEY(user_id,bot_id,request_id));
CREATE TABLE IF NOT EXISTS chat_control_receipts (
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,task_id INTEGER NOT NULL REFERENCES chat_reply_tasks(id) ON DELETE CASCADE,
 request_id TEXT NOT NULL,payload_hash TEXT NOT NULL,response_json TEXT NOT NULL,PRIMARY KEY(user_id,task_id,request_id));
CREATE TABLE IF NOT EXISTS chat_model_calls (
 id TEXT PRIMARY KEY,task_id INTEGER NOT NULL REFERENCES chat_reply_tasks(id) ON DELETE CASCADE,
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,version INTEGER NOT NULL,
 state TEXT NOT NULL,usage_json TEXT,usage_logged INTEGER NOT NULL DEFAULT 0,created_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS chat_tool_attempts (
 task_id INTEGER NOT NULL REFERENCES chat_reply_tasks(id) ON DELETE CASCADE,call_id TEXT NOT NULL,
 tool TEXT NOT NULL,arguments_enc BLOB NOT NULL,state TEXT NOT NULL,result_enc BLOB,action_id INTEGER,
 PRIMARY KEY(task_id,call_id));
'''


def migrate(c, ver):
    for column, ddl in [('message_status',"TEXT NOT NULL DEFAULT 'completed'"),('conversation_generation','INTEGER NOT NULL DEFAULT 1')]:
        _add_column(c,'messages',column,ddl)
    _add_column(c,'owned_tasks','delivery_generation','INTEGER NOT NULL DEFAULT 1')
    for column, ddl in [('chat_task_id','INTEGER REFERENCES chat_reply_tasks(id) ON DELETE SET NULL'),('chat_task_version','INTEGER'),('chat_result_enc','BLOB'),('chat_resolved_at','TEXT')]:
        _add_column(c,'pending_actions',column,ddl)
    for sql in SCHEMA.split(';'):
        if sql.strip():c.execute(sql)
    _add_column(c,"chat_reply_tasks","authorization_json", "TEXT NOT NULL DEFAULT '{}'")
    c.execute("INSERT OR IGNORE INTO conversation_activity SELECT user_id,'private',id,1 FROM bots")
    c.execute("INSERT OR IGNORE INTO conversation_activity SELECT user_id,'group',id,1 FROM chat_groups")
    if ver < 30:
        c.execute("INSERT OR IGNORE INTO message_publications SELECT user_id,'private',bot_id,1,id,1 FROM messages WHERE role='assistant'")
        c.execute("INSERT OR IGNORE INTO message_publications SELECT user_id,'group',group_id,1,id,1 FROM chat_group_messages WHERE role<>'user' AND status IN ('completed','failed','stopped','interrupted')")
        c.execute('INSERT OR IGNORE INTO message_read_receipts SELECT * FROM message_publications')
    # All sources publish in the same transaction that writes a readable message.
    statements=[]
    for table,kind,cid,condition in [('messages','private','bot_id',"NEW.role='assistant' AND NEW.message_status IN ('completed','awaiting_user','awaiting_approval','failed','stopped','interrupted')"),('chat_group_messages','group','group_id',"NEW.role<>'user' AND NEW.status IN ('completed','failed','stopped','interrupted')")]:
        gen = 'NEW.conversation_generation' if kind=='private' else f"COALESCE((SELECT generation FROM conversation_activity WHERE user_id=NEW.user_id AND kind='{kind}' AND conversation_id=NEW.{cid}),1)"
        for op in ['INSERT','UPDATE']:
            changed='' if op=='INSERT' else (' AND (NEW.content<>OLD.content OR NEW.message_status<>OLD.message_status)' if kind=='private' else ' AND (NEW.content<>OLD.content OR NEW.status<>OLD.status)')
            statements.append(f'''CREATE TRIGGER IF NOT EXISTS publish_{kind}_{op.lower()} AFTER {op} ON {table} WHEN {condition}{changed} AND EXISTS(SELECT 1 FROM users WHERE id=NEW.user_id) BEGIN
 INSERT INTO conversation_activity VALUES(NEW.user_id,'{kind}',NEW.{cid},1) ON CONFLICT DO NOTHING;
 INSERT INTO message_publications VALUES(NEW.user_id,'{kind}',NEW.{cid},{gen},NEW.id,1)
 ON CONFLICT(user_id,kind,conversation_id,generation,message_id) DO UPDATE SET publication_revision=publication_revision+1;
 INSERT INTO conversation_events(user_id,kind,conversation_id,generation,event,created_at) VALUES(NEW.user_id,'{kind}',NEW.{cid},{gen},'message_published',NEW.created_at);
END;''')
        statements.append(f'''CREATE TRIGGER IF NOT EXISTS publication_{kind}_delete AFTER DELETE ON {table} WHEN EXISTS(SELECT 1 FROM users WHERE id=OLD.user_id) BEGIN
 DELETE FROM message_publications WHERE user_id=OLD.user_id AND kind='{kind}' AND conversation_id=OLD.{cid} AND message_id=OLD.id;
 DELETE FROM message_read_receipts WHERE user_id=OLD.user_id AND kind='{kind}' AND conversation_id=OLD.{cid} AND message_id=OLD.id;
 INSERT INTO conversation_events(user_id,kind,conversation_id,generation,event,created_at) VALUES(OLD.user_id,'{kind}',OLD.{cid},COALESCE((SELECT generation FROM conversation_activity WHERE user_id=OLD.user_id AND kind='{kind}' AND conversation_id=OLD.{cid}),1),'message_deleted',OLD.created_at);
END;''')
    # Replace this v30 trigger on idempotent init too, including isolated pre-review v30 DBs.
    c.execute("DROP TRIGGER IF EXISTS chat_message_deleted")
    statements.append('''CREATE TRIGGER chat_message_deleted AFTER DELETE ON messages WHEN EXISTS(SELECT 1 FROM users WHERE id=OLD.user_id) BEGIN
 UPDATE messages SET content=CASE WHEN content='' THEN '输入消息已删除，回复已停止' ELSE content||'\n\n输入消息已删除，回复已停止' END,message_status='stopped'
 WHERE user_id=OLD.user_id AND bot_id=OLD.bot_id AND id IN (
   SELECT output_message_id FROM chat_reply_tasks WHERE user_id=OLD.user_id AND bot_id=OLD.bot_id AND input_message_id=OLD.id AND state NOT IN ('completed','failed','stopped','interrupted'));
 INSERT INTO chat_reply_events(user_id,bot_id,task_id,generation,version,event,payload_json,created_at)
 SELECT user_id,bot_id,id,generation,version+1,'task_updated',json_object('reason','message_deleted','message_id',output_message_id),strftime('%Y-%m-%dT%H:%M:%S+00:00','now')
 FROM chat_reply_tasks WHERE user_id=OLD.user_id AND bot_id=OLD.bot_id AND (input_message_id=OLD.id OR output_message_id=OLD.id) AND state NOT IN ('completed','failed','stopped','interrupted');
 UPDATE pending_actions SET status='cancelled',result='关联消息已删除',decided_at=strftime('%Y-%m-%dT%H:%M:%S+00:00','now')
 WHERE user_id=OLD.user_id AND status='pending' AND chat_task_id IN (
   SELECT id FROM chat_reply_tasks WHERE user_id=OLD.user_id AND bot_id=OLD.bot_id AND (input_message_id=OLD.id OR output_message_id=OLD.id) AND state NOT IN ('completed','failed','stopped','interrupted'));
 UPDATE chat_tool_attempts SET state='unknown' WHERE state='running' AND task_id IN (
   SELECT id FROM chat_reply_tasks WHERE user_id=OLD.user_id AND bot_id=OLD.bot_id AND (input_message_id=OLD.id OR output_message_id=OLD.id) AND state NOT IN ('completed','failed','stopped','interrupted'));
 UPDATE chat_reply_tasks SET state='stopped',phase='stopped',version=version+1,lease_token=NULL,updated_at=strftime('%Y-%m-%dT%H:%M:%S+00:00','now') WHERE user_id=OLD.user_id AND bot_id=OLD.bot_id AND (input_message_id=OLD.id OR output_message_id=OLD.id) AND state NOT IN ('completed','failed','stopped','interrupted');
END;''')
    for table,kind,cid in [('chat_reply_tasks','private','bot_id'),('chat_group_tasks','group','group_id'),('owned_tasks','private','owner_bot_id')]:
        for op in ['INSERT','UPDATE','DELETE']:
            ref='OLD' if op=='DELETE' else 'NEW'
            statements.append(f'''CREATE TRIGGER IF NOT EXISTS activity_{table}_{op.lower()} AFTER {op} ON {table} WHEN {ref}.{cid} IS NOT NULL AND EXISTS(SELECT 1 FROM users WHERE id={ref}.user_id) BEGIN
 INSERT INTO conversation_activity VALUES({ref}.user_id,'{kind}',{ref}.{cid},1) ON CONFLICT DO NOTHING;
 INSERT INTO conversation_events(user_id,kind,conversation_id,generation,event,created_at) VALUES({ref}.user_id,'{kind}',{ref}.{cid},COALESCE((SELECT generation FROM conversation_activity WHERE user_id={ref}.user_id AND kind='{kind}' AND conversation_id={ref}.{cid}),1),'activity_updated',{ref}.updated_at);
END;''')
    for sql in statements:c.execute(sql)


def backup_before_v30():
    from pathlib import Path
    from datetime import datetime
    from ..database import DB_PATH
    path=Path(DB_PATH)
    if not path.is_file():return
    source=sqlite3.connect(f'file:{path}?mode=ro',uri=True)
    try:
        try:version=source.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()
        except sqlite3.OperationalError:return
        if not version or int(version[0])>=30:return
        destination=path.with_name(path.name+'.bak-before-v30-'+datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
        target=sqlite3.connect(destination)
        try:source.backup(target)
        finally:target.close()
        destination.chmod(0o600)
    finally:source.close()
