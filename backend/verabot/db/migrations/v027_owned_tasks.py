"""Durable explicitly assigned goals, fenced steps and replayable events."""
SCHEMA='''
CREATE TABLE IF NOT EXISTS owned_tasks (
 id INTEGER PRIMARY KEY,user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 owner_bot_id INTEGER REFERENCES bots(id) ON DELETE SET NULL, owner_name TEXT NOT NULL,
 goal TEXT NOT NULL,completion_criteria TEXT NOT NULL,state TEXT NOT NULL,
 version INTEGER NOT NULL DEFAULT 1,authorization_json TEXT NOT NULL,
 token_limit INTEGER NOT NULL DEFAULT 20000,used_tokens INTEGER NOT NULL DEFAULT 0,reserved_tokens INTEGER NOT NULL DEFAULT 0,
 chain_calls INTEGER NOT NULL DEFAULT 0,chain_output INTEGER NOT NULL DEFAULT 0,
 chain_seconds REAL NOT NULL DEFAULT 0,chain_tools INTEGER NOT NULL DEFAULT 0,
 tainted INTEGER NOT NULL DEFAULT 0,blocker_code TEXT,created_at TEXT NOT NULL,updated_at TEXT NOT NULL,
 request_key TEXT NOT NULL,request_hash TEXT NOT NULL,UNIQUE(user_id,request_key));
CREATE TABLE IF NOT EXISTS owned_steps (
 id INTEGER PRIMARY KEY,task_id INTEGER NOT NULL REFERENCES owned_tasks(id) ON DELETE CASCADE,
 bot_id INTEGER REFERENCES bots(id) ON DELETE SET NULL,version INTEGER NOT NULL,
 kind TEXT NOT NULL DEFAULT 'owner',status TEXT NOT NULL DEFAULT 'queued',
 input_json TEXT NOT NULL DEFAULT '{}',result_json TEXT,action_key TEXT NOT NULL UNIQUE,
 lease_token TEXT,lease_expires_at TEXT,available_at TEXT NOT NULL,
 attempts INTEGER NOT NULL DEFAULT 0,created_at TEXT NOT NULL,
 message_id INTEGER REFERENCES messages(id) ON DELETE SET NULL,delivered_at TEXT);
CREATE UNIQUE INDEX IF NOT EXISTS idx_owned_running ON owned_steps(task_id) WHERE status='running';
CREATE TABLE IF NOT EXISTS owned_inputs (
 id INTEGER PRIMARY KEY,task_id INTEGER NOT NULL REFERENCES owned_tasks(id) ON DELETE CASCADE,
 request_key TEXT NOT NULL,request_hash TEXT NOT NULL,message TEXT NOT NULL,version INTEGER NOT NULL,
 UNIQUE(task_id,request_key));
CREATE TABLE IF NOT EXISTS owned_waits (
 id INTEGER PRIMARY KEY,task_id INTEGER NOT NULL REFERENCES owned_tasks(id) ON DELETE CASCADE,
 step_id INTEGER NOT NULL REFERENCES owned_steps(id) ON DELETE CASCADE,
 version INTEGER NOT NULL,kind TEXT NOT NULL,question TEXT NOT NULL,
 action_id INTEGER REFERENCES pending_actions(id) ON DELETE SET NULL,
 resolved_at TEXT,UNIQUE(step_id));
CREATE TABLE IF NOT EXISTS owned_events (
 id INTEGER PRIMARY KEY AUTOINCREMENT,task_id INTEGER NOT NULL REFERENCES owned_tasks(id) ON DELETE CASCADE,
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,version INTEGER NOT NULL,
 kind TEXT NOT NULL,payload_json TEXT NOT NULL,created_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS owned_calls (
 id TEXT PRIMARY KEY,task_id INTEGER REFERENCES owned_tasks(id) ON DELETE SET NULL,
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 bot_id INTEGER REFERENCES bots(id) ON DELETE SET NULL,
 step_id INTEGER REFERENCES owned_steps(id) ON DELETE SET NULL,
 created_at TEXT NOT NULL,usage_json TEXT,usage_unknown INTEGER NOT NULL DEFAULT 1,
 usage_logged INTEGER NOT NULL DEFAULT 0);
'''
def migrate(c,ver):
 for sql in SCHEMA.split(';'):
  if sql.strip():c.execute(sql)
