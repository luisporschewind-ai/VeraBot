"""v20 -> v21: monotonic revisions for consistent private and group history pages."""
import sqlite3

SCHEMA = """
CREATE TABLE IF NOT EXISTS conversation_revisions (
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 kind TEXT NOT NULL CHECK(kind IN ('private','group')),
 conversation_id INTEGER NOT NULL,
 revision INTEGER NOT NULL DEFAULT 1,
 PRIMARY KEY(user_id,kind,conversation_id)
);
CREATE TRIGGER IF NOT EXISTS sync_private_insert AFTER INSERT ON messages BEGIN
 INSERT INTO conversation_revisions VALUES(NEW.user_id,'private',NEW.bot_id,1)
 ON CONFLICT(user_id,kind,conversation_id) DO UPDATE SET revision=revision+1;
END;
CREATE TRIGGER IF NOT EXISTS sync_private_update AFTER UPDATE OF role,content,traces,created_at ON messages BEGIN
 INSERT INTO conversation_revisions VALUES(NEW.user_id,'private',NEW.bot_id,1)
 ON CONFLICT(user_id,kind,conversation_id) DO UPDATE SET revision=revision+1;
END;
CREATE TRIGGER IF NOT EXISTS sync_private_delete AFTER DELETE ON messages BEGIN
 INSERT INTO conversation_revisions VALUES(OLD.user_id,'private',OLD.bot_id,1)
 ON CONFLICT(user_id,kind,conversation_id) DO UPDATE SET revision=revision+1;
END;
CREATE TRIGGER IF NOT EXISTS sync_feedback_insert AFTER INSERT ON message_feedback BEGIN
 INSERT INTO conversation_revisions(user_id,kind,conversation_id,revision)
 SELECT NEW.user_id,'private',bot_id,1 FROM messages WHERE id=NEW.message_id AND user_id=NEW.user_id
 ON CONFLICT(user_id,kind,conversation_id) DO UPDATE SET revision=revision+1;
END;
CREATE TRIGGER IF NOT EXISTS sync_feedback_update AFTER UPDATE ON message_feedback BEGIN
 INSERT INTO conversation_revisions(user_id,kind,conversation_id,revision)
 SELECT NEW.user_id,'private',bot_id,1 FROM messages WHERE id=NEW.message_id AND user_id=NEW.user_id
 ON CONFLICT(user_id,kind,conversation_id) DO UPDATE SET revision=revision+1;
END;
CREATE TRIGGER IF NOT EXISTS sync_feedback_delete AFTER DELETE ON message_feedback BEGIN
 INSERT INTO conversation_revisions(user_id,kind,conversation_id,revision)
 SELECT OLD.user_id,'private',bot_id,1 FROM messages WHERE id=OLD.message_id AND user_id=OLD.user_id
 ON CONFLICT(user_id,kind,conversation_id) DO UPDATE SET revision=revision+1;
END;
CREATE TRIGGER IF NOT EXISTS sync_attachment_insert AFTER INSERT ON attachments WHEN NEW.message_id IS NOT NULL BEGIN
 INSERT INTO conversation_revisions(user_id,kind,conversation_id,revision)
 SELECT NEW.user_id,'private',bot_id,1 FROM messages WHERE id=NEW.message_id AND user_id=NEW.user_id
 ON CONFLICT(user_id,kind,conversation_id) DO UPDATE SET revision=revision+1;
END;
CREATE TRIGGER IF NOT EXISTS sync_attachment_update AFTER UPDATE ON attachments WHEN NEW.message_id IS NOT NULL BEGIN
 INSERT INTO conversation_revisions(user_id,kind,conversation_id,revision)
 SELECT NEW.user_id,'private',bot_id,1 FROM messages WHERE id=NEW.message_id AND user_id=NEW.user_id
 ON CONFLICT(user_id,kind,conversation_id) DO UPDATE SET revision=revision+1;
END;
CREATE TRIGGER IF NOT EXISTS sync_attachment_delete AFTER DELETE ON attachments WHEN OLD.message_id IS NOT NULL BEGIN
 INSERT INTO conversation_revisions(user_id,kind,conversation_id,revision)
 SELECT OLD.user_id,'private',bot_id,1 FROM messages WHERE id=OLD.message_id AND user_id=OLD.user_id
 ON CONFLICT(user_id,kind,conversation_id) DO UPDATE SET revision=revision+1;
END;
CREATE TRIGGER IF NOT EXISTS sync_group_insert AFTER INSERT ON chat_group_messages BEGIN
 INSERT INTO conversation_revisions VALUES(NEW.user_id,'group',NEW.group_id,1)
 ON CONFLICT(user_id,kind,conversation_id) DO UPDATE SET revision=revision+1;
END;
CREATE TRIGGER IF NOT EXISTS sync_group_update AFTER UPDATE OF role,content,status,member_id,sender_name_snapshot,sender_appearance_snapshot,usage_json,finished_at ON chat_group_messages BEGIN
 INSERT INTO conversation_revisions VALUES(NEW.user_id,'group',NEW.group_id,1)
 ON CONFLICT(user_id,kind,conversation_id) DO UPDATE SET revision=revision+1;
END;
CREATE TRIGGER IF NOT EXISTS sync_group_delete AFTER DELETE ON chat_group_messages BEGIN
 INSERT INTO conversation_revisions VALUES(OLD.user_id,'group',OLD.group_id,1)
 ON CONFLICT(user_id,kind,conversation_id) DO UPDATE SET revision=revision+1;
END;
"""

def migrate(c, ver: int) -> None:
    statement = ""
    for character in SCHEMA:
        statement += character
        if character == ";" and sqlite3.complete_statement(statement):
            c.execute(statement)
            statement = ""
    if statement.strip():
        raise sqlite3.OperationalError("incomplete conversation sync migration statement")
    c.execute("""INSERT OR IGNORE INTO conversation_revisions(user_id,kind,conversation_id,revision)
                 SELECT user_id,'private',bot_id,1 FROM messages GROUP BY user_id,bot_id""")
    c.execute("""INSERT OR IGNORE INTO conversation_revisions(user_id,kind,conversation_id,revision)
                 SELECT user_id,'group',id,1 FROM chat_groups""")
