"""v13 → v14：记忆 M2（滚动摘要 + 风格校准，MEMORY_GROWTH §11.1）。

只建表，不回填；memories 表 v4 起已支持 scope='summary' 与 type='style'，无需改列。

memory_jobs：进程内 worker 的任务队列（摘要 / 以后的抽取、回顾）。部分唯一索引保证同一
(user, bot, kind) 同时只有一个 pending/running 任务，入队用 INSERT OR IGNORE 幂等。
message_feedback：消息级 👍 / 👎，(user_id, message_id) 唯一 —— 同一消息可改评（upsert）。
"""
from ._util import _columns  # noqa: F401  （保持与其它迁移一致的导入风格，目前用不到）


MEMORY_M2_SCHEMA = """
CREATE TABLE IF NOT EXISTS memory_jobs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  bot_id INTEGER REFERENCES bots(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK(kind IN ('summarize','extract','review')),
  status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','running','done','failed','skipped')),
  after_message_id INTEGER,                              -- 触发时该 Bot 的最新消息 id
  attempts INTEGER NOT NULL DEFAULT 0,
  error TEXT,
  created_at TEXT NOT NULL,
  finished_at TEXT
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_memjob_open
  ON memory_jobs(user_id, bot_id, kind) WHERE status IN ('pending','running');
CREATE INDEX IF NOT EXISTS idx_memjob_pick ON memory_jobs(status, id);

CREATE TABLE IF NOT EXISTS message_feedback (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  bot_id INTEGER REFERENCES bots(id) ON DELETE CASCADE,
  message_id INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  rating INTEGER NOT NULL CHECK(rating IN (-1, 1)),
  reason TEXT CHECK(reason IN ('too_long','too_short','inaccurate','tone','other')),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(user_id, message_id)
);
CREATE INDEX IF NOT EXISTS idx_feedback_recent ON message_feedback(user_id, bot_id, reason, created_at);
"""


def migrate_memory_m2(c):
    """v13 → v14：只建 memory_jobs / message_feedback 表。幂等。"""
    c.executescript(MEMORY_M2_SCHEMA)


def migrate(c, ver: int) -> None:
    migrate_memory_m2(c)
