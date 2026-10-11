"""v19 → v20: independent group conversations; private history is untouched."""

SCHEMA = """
CREATE TABLE IF NOT EXISTS chat_groups (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 name TEXT NOT NULL,
 default_bot_id INTEGER REFERENCES bots(id) ON DELETE SET NULL,
 created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_groups_user ON chat_groups(user_id,id);
CREATE TABLE IF NOT EXISTS chat_group_members (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 group_id INTEGER NOT NULL REFERENCES chat_groups(id) ON DELETE CASCADE,
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 bot_id INTEGER REFERENCES bots(id) ON DELETE SET NULL,
 position INTEGER NOT NULL,
 name_snapshot TEXT NOT NULL, appearance_snapshot TEXT NOT NULL,
 UNIQUE(group_id,position), UNIQUE(group_id,bot_id)
);
CREATE TABLE IF NOT EXISTS chat_group_turns (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 group_id INTEGER NOT NULL REFERENCES chat_groups(id) ON DELETE CASCADE,
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 client_request_id TEXT NOT NULL, request_hash TEXT NOT NULL,
 mode TEXT NOT NULL CHECK(mode IN ('single','round')),
 target_member_id INTEGER REFERENCES chat_group_members(id) ON DELETE SET NULL,
 retry_of_message_id INTEGER REFERENCES chat_group_messages(id) ON DELETE SET NULL,
 user_message_id INTEGER REFERENCES chat_group_messages(id) ON DELETE SET NULL,
 context_end_message_id INTEGER,
 status TEXT NOT NULL CHECK(status IN ('running','completed','partial','stopped','failed','interrupted')),
 cancel_requested INTEGER NOT NULL DEFAULT 0,
 created_at TEXT NOT NULL, finished_at TEXT,
 UNIQUE(user_id,group_id,client_request_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_group_running ON chat_group_turns(group_id) WHERE status='running';
CREATE TABLE IF NOT EXISTS chat_group_messages (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 group_id INTEGER NOT NULL REFERENCES chat_groups(id) ON DELETE CASCADE,
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 turn_id INTEGER NOT NULL REFERENCES chat_group_turns(id) ON DELETE CASCADE,
 role TEXT NOT NULL CHECK(role IN ('user','bot')),
 member_id INTEGER REFERENCES chat_group_members(id) ON DELETE SET NULL,
 content TEXT NOT NULL DEFAULT '',
 status TEXT NOT NULL CHECK(status IN ('streaming','completed','failed','stopped','interrupted')),
 sender_name_snapshot TEXT, sender_appearance_snapshot TEXT,
 usage_json TEXT, usage_logged INTEGER NOT NULL DEFAULT 0,
 created_at TEXT NOT NULL, finished_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_group_messages ON chat_group_messages(user_id,group_id,id);
"""

def migrate(c, ver: int) -> None:
    # Do not use executescript: it implicitly commits the caller's migration transaction.
    for statement in SCHEMA.split(";"):
        if statement.strip():
            c.execute(statement)
