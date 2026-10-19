"""v38: durable, isolated Tetris sessions, idempotency, events and worker health."""
import sqlite3
from datetime import datetime
from pathlib import Path

SCHEMA='''
CREATE TABLE IF NOT EXISTS tetris_sessions(
 id TEXT PRIMARY KEY,user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 bot_id INTEGER REFERENCES bots(id) ON DELETE SET NULL,origin_client_id TEXT NOT NULL,
 controller TEXT NOT NULL CHECK(controller IN ('player','bot')),
 run_state TEXT NOT NULL CHECK(run_state IN ('running','paused','reclaimPending','ended')),
 version INTEGER NOT NULL,control_epoch INTEGER NOT NULL,snapshot_json TEXT NOT NULL,
 pending_request_id TEXT,pending_clear_controller TEXT,
 player_score INTEGER NOT NULL,player_lines INTEGER NOT NULL,bot_score INTEGER NOT NULL,bot_lines INTEGER NOT NULL,
 lease_owner TEXT,lease_token TEXT,lease_expires REAL,next_due REAL NOT NULL,
 updated_at REAL NOT NULL,ended_at REAL);
CREATE UNIQUE INDEX IF NOT EXISTS tetris_one_bot_round ON tetris_sessions(user_id)
 WHERE controller='bot' AND run_state!='ended';
CREATE INDEX IF NOT EXISTS tetris_due ON tetris_sessions(run_state,next_due,lease_expires);
CREATE TABLE IF NOT EXISTS tetris_operations(
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,request_id TEXT NOT NULL,
 session_id TEXT NOT NULL REFERENCES tetris_sessions(id) ON DELETE CASCADE,
 payload_hash TEXT NOT NULL,result_json TEXT NOT NULL,status TEXT NOT NULL,
 PRIMARY KEY(user_id,request_id));
CREATE TABLE IF NOT EXISTS tetris_events(
 session_id TEXT NOT NULL REFERENCES tetris_sessions(id) ON DELETE CASCADE,
 event_sequence INTEGER NOT NULL,logical_time_ms INTEGER NOT NULL,kind TEXT NOT NULL,
 controller TEXT NOT NULL,payload_json TEXT NOT NULL,
 PRIMARY KEY(session_id,event_sequence));
CREATE TABLE IF NOT EXISTS tetris_workers(
 owner TEXT PRIMARY KEY,heartbeat REAL NOT NULL,rule_version TEXT NOT NULL,fixture_sha256 TEXT NOT NULL);
'''

def migrate(c,ver):
    for statement in SCHEMA.split(';'):
        if statement.strip():c.execute(statement)

def backup_before_v38():
    from ..database import DB_PATH
    path=Path(DB_PATH)
    if not path.is_file():return
    source=sqlite3.connect(f'file:{path}?mode=ro',uri=True)
    try:
        try:version=source.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()
        except sqlite3.OperationalError:return
        if not version or int(version[0])>=38:return
        destination=path.with_name(path.name+'.bak-before-v38-'+datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
        target=sqlite3.connect(destination)
        try:source.backup(target)
        finally:target.close()
        destination.chmod(0o600)
    finally:source.close()
