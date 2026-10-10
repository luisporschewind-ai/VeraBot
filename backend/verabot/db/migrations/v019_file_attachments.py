"""v18 → v19：允许安全存储可读文件附件，保留既有图片记录。"""

def migrate(c, ver: int) -> None:
    if ver >= 19:
        return
    c.execute("ALTER TABLE attachments RENAME TO attachments_v18")
    c.execute("""
    CREATE TABLE attachments (
      id TEXT PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      bot_id INTEGER REFERENCES bots(id) ON DELETE CASCADE,
      message_id INTEGER REFERENCES messages(id) ON DELETE CASCADE,
      kind TEXT NOT NULL CHECK(kind IN ('image','file')),
      mime TEXT NOT NULL, bytes INTEGER NOT NULL, width INTEGER NOT NULL DEFAULT 0,
      height INTEGER NOT NULL DEFAULT 0, sha256 TEXT NOT NULL,
      storage_backend TEXT NOT NULL DEFAULT 'local', storage_key TEXT NOT NULL,
      thumb_key TEXT, caption TEXT, caption_status TEXT,
      status TEXT NOT NULL CHECK(status IN ('pending','attached')),
      created_at TEXT NOT NULL, expires_at TEXT,
      filename TEXT, extension TEXT, text_key TEXT, text_bytes INTEGER NOT NULL DEFAULT 0, text_status TEXT,
      text_chars INTEGER NOT NULL DEFAULT 0, page_count INTEGER
    )""")
    c.execute("""INSERT INTO attachments(id,user_id,bot_id,message_id,kind,mime,bytes,width,height,sha256,
      storage_backend,storage_key,thumb_key,caption,caption_status,status,created_at,expires_at)
    SELECT id,user_id,bot_id,message_id,kind,mime,bytes,width,height,sha256,
      storage_backend,storage_key,thumb_key,caption,caption_status,status,created_at,expires_at
    FROM attachments_v18""")
    c.execute("DROP TABLE attachments_v18")
    c.execute("CREATE INDEX idx_att_user ON attachments(user_id, message_id)")
