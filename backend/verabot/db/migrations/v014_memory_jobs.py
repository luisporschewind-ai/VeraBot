"""v13 → v14：记忆 M2（滚动摘要任务 + 消息反馈）。

只建表，不写记忆、不改已有行。见 docs/design/MEMORY_GROWTH.md §3.2 / §11.1。
"""

MEMORY_JOBS_SCHEMA = """
CREATE TABLE IF NOT EXISTS memory_jobs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  bot_id INTEGER NOT NULL REFERENCES bots(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('summarize','extract','review')),
  status TEXT NOT NULL CHECK (status IN ('pending','running','done','failed','skipped')),
  after_message_id INTEGER REFERENCES messages(id) ON DELETE SET NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  error TEXT,
  created_at TEXT NOT NULL,
  finished_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_mem_jobs_status ON memory_jobs(status, id);
CREATE INDEX IF NOT EXISTS idx_mem_jobs_user ON memory_jobs(user_id, bot_id, kind, status);

CREATE TABLE IF NOT EXISTS message_feedback (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  bot_id INTEGER NOT NULL REFERENCES bots(id) ON DELETE CASCADE,
  message_id INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  rating INTEGER NOT NULL CHECK (rating IN (1, -1)),
  reason TEXT CHECK (reason IS NULL OR reason IN ('too_long','too_short','inaccurate','tone','other')),
  created_at TEXT NOT NULL,
  UNIQUE(user_id, message_id)
);
CREATE INDEX IF NOT EXISTS idx_feedback_style ON message_feedback(user_id, bot_id, reason, created_at);
"""


def migrate(c, ver: int) -> None:
    c.executescript(MEMORY_JOBS_SCHEMA)
