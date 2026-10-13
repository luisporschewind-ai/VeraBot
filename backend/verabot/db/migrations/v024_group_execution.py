"""v23 → v24: durable, versioned group execution and handoff state."""
from ._util import _add_column

SCHEMA = """
CREATE TABLE IF NOT EXISTS chat_group_tasks (
 id INTEGER PRIMARY KEY, group_id INTEGER NOT NULL REFERENCES chat_groups(id) ON DELETE CASCADE,
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 goal TEXT NOT NULL, state TEXT NOT NULL CHECK(state IN ('queued','running','awaiting_user','completed','stopped','failed','interrupted')),
 version INTEGER NOT NULL DEFAULT 1, owner_member_id INTEGER REFERENCES chat_group_members(id) ON DELETE SET NULL,
 root_message_id INTEGER REFERENCES chat_group_messages(id) ON DELETE SET NULL,
 created_at TEXT NOT NULL, updated_at TEXT NOT NULL, finished_at TEXT
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_group_one_active_task ON chat_group_tasks(group_id)
 WHERE state IN ('queued','running','awaiting_user');
CREATE INDEX IF NOT EXISTS idx_group_task_user ON chat_group_tasks(user_id,group_id,id);
CREATE TABLE IF NOT EXISTS chat_group_task_inputs (
 id INTEGER PRIMARY KEY, task_id INTEGER NOT NULL REFERENCES chat_group_tasks(id) ON DELETE CASCADE,
 group_id INTEGER NOT NULL REFERENCES chat_groups(id) ON DELETE CASCADE,
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 client_request_id TEXT NOT NULL, request_hash TEXT NOT NULL, message TEXT NOT NULL,
 turn_id INTEGER REFERENCES chat_group_turns(id) ON DELETE SET NULL,
 call_count INTEGER NOT NULL DEFAULT 0, elapsed_ms INTEGER NOT NULL DEFAULT 0,
 created_at TEXT NOT NULL, UNIQUE(user_id,group_id,client_request_id)
);
CREATE TABLE IF NOT EXISTS chat_group_steps (
 id INTEGER PRIMARY KEY, task_id INTEGER NOT NULL REFERENCES chat_group_tasks(id) ON DELETE CASCADE,
 input_id INTEGER NOT NULL REFERENCES chat_group_task_inputs(id) ON DELETE CASCADE,
 group_id INTEGER NOT NULL REFERENCES chat_groups(id) ON DELETE CASCADE,
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 kind TEXT NOT NULL CHECK(kind IN ('route','member')), action_key TEXT UNIQUE,
 version INTEGER NOT NULL, member_id INTEGER REFERENCES chat_group_members(id) ON DELETE SET NULL,
 status TEXT NOT NULL CHECK(status IN ('queued','running','completed','failed','stopped','interrupted','awaiting_user')),
 input_json TEXT NOT NULL DEFAULT '{}', result_json TEXT, consult_return_step_id INTEGER REFERENCES chat_group_steps(id) ON DELETE SET NULL,
 issue_key TEXT, lease_token TEXT, lease_expires_at TEXT, started_at TEXT, finished_at TEXT,
 created_at TEXT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_group_one_running_step ON chat_group_steps(group_id) WHERE status='running';
CREATE INDEX IF NOT EXISTS idx_group_step_queue ON chat_group_steps(status,group_id,id);
CREATE TABLE IF NOT EXISTS chat_group_clarifications (
 id INTEGER PRIMARY KEY, task_id INTEGER NOT NULL REFERENCES chat_group_tasks(id) ON DELETE CASCADE,
 group_id INTEGER NOT NULL REFERENCES chat_groups(id) ON DELETE CASCADE,
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 owner_member_id INTEGER REFERENCES chat_group_members(id) ON DELETE SET NULL,
 original_request TEXT NOT NULL, missing_information TEXT NOT NULL,
 latest_question_message_id INTEGER REFERENCES chat_group_messages(id) ON DELETE SET NULL,
 status TEXT NOT NULL CHECK(status IN ('active','awaiting_user','resolved','cancelled')),
 created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_group_active_clarification ON chat_group_clarifications(group_id)
 WHERE status IN ('active','awaiting_user');
CREATE TABLE IF NOT EXISTS chat_group_events (
 id INTEGER PRIMARY KEY, group_id INTEGER NOT NULL REFERENCES chat_groups(id) ON DELETE CASCADE,
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 task_id INTEGER REFERENCES chat_group_tasks(id) ON DELETE CASCADE,
 version INTEGER NOT NULL, kind TEXT NOT NULL, payload_json TEXT NOT NULL,
 created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_group_events_cursor ON chat_group_events(group_id,id);
CREATE TABLE IF NOT EXISTS chat_group_usage_calls (
 id INTEGER PRIMARY KEY, call_id TEXT NOT NULL UNIQUE, user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 group_id INTEGER NOT NULL REFERENCES chat_groups(id) ON DELETE CASCADE,
 task_id INTEGER REFERENCES chat_group_tasks(id) ON DELETE SET NULL,
 step_id INTEGER REFERENCES chat_group_steps(id) ON DELETE SET NULL,
 kind TEXT NOT NULL CHECK(kind IN ('group_routing','group_chat')),
 usage_log_id INTEGER REFERENCES usage_log(id) ON DELETE SET NULL,
 usage_json TEXT, usage_unknown INTEGER NOT NULL DEFAULT 0,
 created_at TEXT NOT NULL
);
"""


def migrate(c, ver: int) -> None:
    for statement in SCHEMA.split(";"):
        if statement.strip():
            c.execute(statement)
    _add_column(c, "chat_group_members", "last_clarified_at", "TEXT")
    if ver < 24:
        c.execute("UPDATE chat_groups SET default_bot_id=NULL")
