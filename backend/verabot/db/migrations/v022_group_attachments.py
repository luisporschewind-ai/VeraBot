"""v21 -> v22: group-scoped attachments on group messages."""

SCHEMA = """
CREATE TABLE IF NOT EXISTS chat_group_attachments (
 attachment_id TEXT PRIMARY KEY REFERENCES attachments(id) ON DELETE CASCADE,
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 group_id INTEGER NOT NULL REFERENCES chat_groups(id) ON DELETE CASCADE,
 message_id INTEGER NOT NULL REFERENCES chat_group_messages(id) ON DELETE CASCADE,
 created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_group_attachments_message
 ON chat_group_attachments(user_id,group_id,message_id);
"""


def migrate(c, ver: int) -> None:
    for statement in SCHEMA.split(";"):
        if statement.strip():
            c.execute(statement)
