"""v15 → v16：月度回顾缓存与账号级 review job。"""

def migrate(c, ver: int) -> None:
    if ver >= 16:
        return
    c.execute("""CREATE TABLE IF NOT EXISTS memory_jobs_v16 (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      bot_id INTEGER REFERENCES bots(id) ON DELETE CASCADE,
      kind TEXT NOT NULL CHECK (kind IN ('summarize','extract','review')),
      status TEXT NOT NULL CHECK (status IN ('pending','running','done','failed','skipped')),
      after_message_id INTEGER REFERENCES messages(id) ON DELETE SET NULL,
      attempts INTEGER NOT NULL DEFAULT 0, error TEXT, created_at TEXT NOT NULL, finished_at TEXT, review_month TEXT,
      CHECK ((kind='review' AND bot_id IS NULL) OR (kind IN ('summarize','extract') AND bot_id IS NOT NULL))
    )""")
    c.execute("INSERT OR IGNORE INTO memory_jobs_v16(id,user_id,bot_id,kind,status,after_message_id,attempts,error,created_at,finished_at) SELECT id,user_id,bot_id,kind,status,after_message_id,attempts,error,created_at,finished_at FROM memory_jobs")
    c.execute("DROP TABLE memory_jobs")
    c.execute("ALTER TABLE memory_jobs_v16 RENAME TO memory_jobs")
    c.execute("CREATE INDEX IF NOT EXISTS idx_mem_jobs_status ON memory_jobs(status,id)")
    c.execute("CREATE INDEX IF NOT EXISTS idx_mem_jobs_user ON memory_jobs(user_id,bot_id,kind,status)")
    c.execute("""CREATE TABLE IF NOT EXISTS reviews (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      month TEXT NOT NULL CHECK (month GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]'),
      status TEXT NOT NULL CHECK (status IN ('pending','ready','unavailable')),
      content TEXT NOT NULL DEFAULT '{}', total_tokens INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, UNIQUE(user_id,month)
    )""")
    c.execute("CREATE INDEX IF NOT EXISTS idx_reviews_user_month ON reviews(user_id,month)")
    c.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_mem_jobs_review_month ON memory_jobs(user_id,review_month) WHERE kind='review'")
