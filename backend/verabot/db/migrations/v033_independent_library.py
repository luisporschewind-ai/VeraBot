"""v33: durable library metadata independent of conversation foreign keys."""
SCHEMA = '''
CREATE TABLE IF NOT EXISTS library_items(
 id TEXT PRIMARY KEY,user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 payload TEXT NOT NULL,created_at TEXT NOT NULL,revision INTEGER NOT NULL DEFAULT 0,deleted INTEGER NOT NULL DEFAULT 0);
CREATE INDEX IF NOT EXISTS library_user ON library_items(user_id,created_at,id);
CREATE TABLE IF NOT EXISTS library_bot_links(
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,item_id TEXT NOT NULL REFERENCES library_items(id) ON DELETE CASCADE,
 bot_id INTEGER NOT NULL REFERENCES bots(id) ON DELETE CASCADE,version INTEGER NOT NULL,PRIMARY KEY(user_id,item_id,bot_id));
CREATE TABLE IF NOT EXISTS library_unlinked(
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,item_id TEXT NOT NULL REFERENCES library_items(id) ON DELETE CASCADE,
 bot_id INTEGER NOT NULL,PRIMARY KEY(user_id,item_id,bot_id));
CREATE TABLE IF NOT EXISTS library_sources(
 item_id TEXT NOT NULL REFERENCES library_items(id) ON DELETE CASCADE,user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 source_key TEXT NOT NULL,kind TEXT NOT NULL,source_id INTEGER,bot_id INTEGER,display_name TEXT NOT NULL,message_id INTEGER,created_at TEXT NOT NULL,
 PRIMARY KEY(item_id,source_key));
CREATE TABLE IF NOT EXISTS library_changes(id INTEGER PRIMARY KEY AUTOINCREMENT,user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,item_id TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS library_changes_user ON library_changes(user_id,id);
CREATE TABLE IF NOT EXISTS library_upload_keys(user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,request_key TEXT NOT NULL,item_id TEXT NOT NULL,PRIMARY KEY(user_id,request_key));
'''

def migrate(c, ver):
    for statement in SCHEMA.split(';'):
        if statement.strip(): c.execute(statement)
    for table, kind in [('messages','private'),('chat_group_messages','group')]:
        c.execute(f"""CREATE TRIGGER IF NOT EXISTS library_source_{kind}_deleted AFTER DELETE ON {table}
          WHEN EXISTS(SELECT 1 FROM users WHERE id=OLD.user_id)
          BEGIN
          INSERT INTO library_changes(user_id,item_id) SELECT user_id,item_id FROM library_sources
          WHERE user_id=OLD.user_id AND kind='{kind}' AND message_id=OLD.id;
          UPDATE library_items SET revision=(SELECT MAX(id) FROM library_changes WHERE user_id=OLD.user_id)
          WHERE user_id=OLD.user_id AND id IN (SELECT item_id FROM library_sources WHERE user_id=OLD.user_id AND kind='{kind}' AND message_id=OLD.id);
          END""")
    c.execute("""CREATE TRIGGER IF NOT EXISTS library_link_deleted AFTER DELETE ON library_bot_links
      WHEN EXISTS(SELECT 1 FROM users WHERE id=OLD.user_id)
      BEGIN INSERT INTO library_changes(user_id,item_id) VALUES(OLD.user_id,OLD.item_id);
      UPDATE library_items SET revision=last_insert_rowid() WHERE id=OLD.item_id AND user_id=OLD.user_id; END""")
    if ver >= 33: return
    from ..library_store import ingest
    for row in c.execute("SELECT * FROM attachments WHERE status='attached'").fetchall():
        row = dict(row)
        group = c.execute('SELECT group_id,message_id FROM chat_group_attachments WHERE attachment_id=? AND user_id=?',(row['id'],row['user_id'])).fetchone()
        if group:
            row['message_id'] = group['message_id']
            ingest(c,row,'group',group['group_id'],None)
        else: ingest(c,row,'private' if row['message_id'] else 'upload',row['bot_id'],row['bot_id'])

def backup_before_v33(path=None):
    import sqlite3
    import time
    from pathlib import Path
    from ..database import DB_PATH
    path=Path(path or DB_PATH)
    if not path.is_file(): return None
    source=sqlite3.connect(path)
    try:
        try: version=source.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()
        except sqlite3.OperationalError: return None
        if not version or int(version[0])>=33: return None
        target=path.with_name(path.name+f'.bak-before-v33-{time.time_ns()}')
        with sqlite3.connect(target) as destination: source.backup(destination)
        target.chmod(0o600)
        return target
    finally: source.close()
