"""v11 → v12：图片附件表（依赖 v11 提醒 R1）。

只建表，不回填。文件在磁盘（DATA_DIR/attachments），这里只存元数据和相对路径（storage_key）。
storage_backend 预留给以后换对象存储（默认 local）；换存储只改实现，不改表。
message_id 随消息级联删除；bot_id / user_id 随 Bot / 账号级联删除。行删掉后磁盘文件由调用方
（或启动对账）删除，见 services/attachments/repo.py；SQL 见 db/attachment_store.py。
"""

ATTACHMENT_SCHEMA = """
CREATE TABLE IF NOT EXISTS attachments (
  id TEXT PRIMARY KEY,                                   -- att_<base32>
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  bot_id INTEGER REFERENCES bots(id) ON DELETE CASCADE,
  message_id INTEGER REFERENCES messages(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK(kind IN ('image')),
  mime TEXT NOT NULL,
  bytes INTEGER NOT NULL,
  width INTEGER NOT NULL,
  height INTEGER NOT NULL,
  sha256 TEXT NOT NULL,
  storage_backend TEXT NOT NULL DEFAULT 'local',
  storage_key TEXT NOT NULL,                             -- u<user>/<xx>/att_<id>.<ext>
  thumb_key TEXT,
  caption TEXT,                                          -- 首次看图后由模型生成的描述（按需召回用）
  caption_status TEXT,                                   -- NULL / ok / failed
  status TEXT NOT NULL CHECK(status IN ('pending','attached')),
  created_at TEXT NOT NULL,
  expires_at TEXT                                        -- 仅 pending：过期后由对账删除
);
CREATE INDEX IF NOT EXISTS idx_att_user ON attachments(user_id, message_id);
"""


def migrate_attachments(c):
    """v11 → v12：只建 attachments 表。幂等。"""
    c.executescript(ATTACHMENT_SCHEMA)


def migrate(c, ver: int) -> None:
    migrate_attachments(c)
