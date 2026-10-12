"""v21: persistent scheduled tasks; API and standalone worker share this queue."""
from ._util import _add_column

SCHEMA = """
CREATE TABLE IF NOT EXISTS scheduled_tasks (
 id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 bot_id INTEGER REFERENCES bots(id) ON DELETE SET NULL,
 title TEXT NOT NULL, instruction TEXT NOT NULL,
 state TEXT NOT NULL CHECK(state IN ('active','paused','completed','deleted')),
 timezone TEXT NOT NULL, start_at_utc TEXT NOT NULL, rrule TEXT,
 next_run_at_utc TEXT, misfire_policy TEXT NOT NULL DEFAULT 'skip' CHECK(misfire_policy IN ('skip','latest')),
 schedule_revision INTEGER NOT NULL DEFAULT 1, version INTEGER NOT NULL DEFAULT 1,
 repeat TEXT NOT NULL DEFAULT 'once', weekdays_json TEXT NOT NULL DEFAULT '[]',
 pause_reason TEXT, authorized_tools_json TEXT NOT NULL DEFAULT '{}',
 idempotency_key TEXT, request_hash TEXT,
 created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT,
 UNIQUE(user_id,idempotency_key)
);
CREATE INDEX IF NOT EXISTS idx_task_due ON scheduled_tasks(state,next_run_at_utc);
CREATE TABLE IF NOT EXISTS scheduled_task_runs (
 id INTEGER PRIMARY KEY, task_id INTEGER NOT NULL REFERENCES scheduled_tasks(id) ON DELETE CASCADE,
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 bot_id INTEGER REFERENCES bots(id) ON DELETE SET NULL,
 trigger TEXT NOT NULL CHECK(trigger IN ('scheduled','manual')),
 scheduled_for_utc TEXT NOT NULL, schedule_revision INTEGER NOT NULL,
 idempotency_key TEXT, request_hash TEXT,
 state TEXT NOT NULL CHECK(state IN ('queued','running','retry_wait','succeeded','failed','interrupted','skipped','cancelled')),
 task_snapshot_json TEXT NOT NULL, available_at TEXT NOT NULL, created_at TEXT NOT NULL,
 lease_owner TEXT, lease_token TEXT, lease_expires_at TEXT,
 cancel_requested INTEGER NOT NULL DEFAULT 0, attempt_count INTEGER NOT NULL DEFAULT 0,
 started_at TEXT, finished_at TEXT, result_text TEXT, error_code TEXT, error_summary TEXT,
 message_id INTEGER REFERENCES messages(id) ON DELETE SET NULL,
 notification_id INTEGER REFERENCES notifications(id) ON DELETE SET NULL, delivered_at TEXT,
 UNIQUE(task_id,schedule_revision,scheduled_for_utc,trigger),
 UNIQUE(user_id,task_id,idempotency_key)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_task_active_run ON scheduled_task_runs(task_id)
 WHERE state IN ('queued','running','retry_wait');
CREATE INDEX IF NOT EXISTS idx_run_queue ON scheduled_task_runs(state,available_at);
CREATE TABLE IF NOT EXISTS scheduled_task_attempts (
 id INTEGER PRIMARY KEY, run_id INTEGER NOT NULL REFERENCES scheduled_task_runs(id) ON DELETE CASCADE,
 attempt_number INTEGER NOT NULL, state TEXT NOT NULL DEFAULT 'running',
 started_at TEXT NOT NULL, finished_at TEXT, usage_json TEXT, usage_unknown INTEGER NOT NULL DEFAULT 0,
 error_code TEXT, trace_summary_json TEXT, UNIQUE(run_id,attempt_number)
);
"""
def migrate(c, ver):
    for statement in SCHEMA.split(';'):
        if statement.strip():
            c.execute(statement)
    _add_column(c, 'messages', 'source_kind', 'TEXT')
    _add_column(c, 'messages', 'source_id', 'INTEGER')
    c.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_message_task_source ON messages(source_kind,source_id) WHERE source_kind='scheduled_task'")
