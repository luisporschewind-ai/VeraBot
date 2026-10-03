"""v1 基础表（以及后续版本直接写进基础 DDL 的表：头像 v3、记忆 v4）。每次启动都执行（全部 IF NOT EXISTS）。"""

SCHEMA = """
PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS bots (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  avatar TEXT NOT NULL DEFAULT '🤖',
  color TEXT NOT NULL DEFAULT '#0F766E',
  persona TEXT NOT NULL DEFAULT '',
  instructions TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  UNIQUE(user_id, name)
);
CREATE TABLE IF NOT EXISTS messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  bot_id INTEGER NOT NULL REFERENCES bots(id) ON DELETE CASCADE,
  role TEXT NOT NULL,              -- user / assistant
  content TEXT NOT NULL,
  traces TEXT,                     -- JSON: 本轮工具调用 / 多 Agent 交接记录
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_msg_bot ON messages(user_id, bot_id, id);
CREATE TABLE IF NOT EXISTS reminders (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  bot_id INTEGER REFERENCES bots(id) ON DELETE SET NULL,
  content TEXT NOT NULL,
  due_at TEXT,
  done INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS delegations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  from_bot_id INTEGER NOT NULL,
  to_bot_id INTEGER NOT NULL,
  question TEXT NOT NULL,
  shared_context TEXT,
  answer TEXT,
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS usage_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  bot_id INTEGER,
  kind TEXT NOT NULL,              -- chat / delegation
  prompt_tokens INTEGER NOT NULL DEFAULT 0,
  completion_tokens INTEGER NOT NULL DEFAULT 0,
  total_tokens INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_usage_user ON usage_log(user_id, created_at);
CREATE TABLE IF NOT EXISTS transcriptions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  model TEXT NOT NULL,
  bytes INTEGER NOT NULL DEFAULT 0,
  duration_s REAL,
  chars INTEGER NOT NULL DEFAULT 0,
  total_tokens INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_tr_user ON transcriptions(user_id, created_at);
-- 自定义头像（Custom avatars）。bot_id=0 表示用户自己的头像；正数为 Bot id。
-- 图片统一存成 JPEG。bots.avatar 仍是表情符号（emoji），与照片互不覆盖。
CREATE TABLE IF NOT EXISTS avatars (
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  bot_id INTEGER NOT NULL DEFAULT 0,
  content_type TEXT NOT NULL,
  data BLOB NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (user_id, bot_id)
);
CREATE TRIGGER IF NOT EXISTS avatars_delete_with_bot
AFTER DELETE ON bots
FOR EACH ROW
BEGIN
  DELETE FROM avatars WHERE user_id = OLD.user_id AND bot_id = OLD.id;
END;
-- v4：长期记忆（Memories）。所有查询必须带 user_id。见 docs/design/MEMORY_GROWTH.md §3
CREATE TABLE IF NOT EXISTS memories (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  scope TEXT NOT NULL CHECK (scope IN ('global','bot','summary')),
  bot_id INTEGER REFERENCES bots(id) ON DELETE CASCADE,            -- scope=bot/summary 必填；global 为 NULL
  type TEXT NOT NULL CHECK (type IN ('profile','preference','fact','style','summary','routine')),
  content TEXT NOT NULL,                                           -- 明文正文；敏感记忆只存占位「[健康信息]」；rejected/expired 清空
  content_enc TEXT,                                                -- 敏感记忆（health / finance）的 Fernet 密文
  content_hash TEXT NOT NULL,                                      -- 规范化正文的哈希（敏感记忆用 HMAC）：去重 + 拒绝冷却
  source TEXT NOT NULL,                                            -- explicit_chat / memory_page / feedback / summary_job / implicit_extraction / suggestion
  source_bot_id INTEGER REFERENCES bots(id) ON DELETE SET NULL,
  source_message_id INTEGER REFERENCES messages(id) ON DELETE SET NULL,
  confidence REAL NOT NULL DEFAULT 1.0,
  status TEXT NOT NULL CHECK (status IN ('proposed','candidate','active','rejected','expired')),
  sensitivity TEXT NOT NULL DEFAULT 'normal' CHECK (sensitivity IN ('normal','health','finance')),
  action TEXT NOT NULL DEFAULT 'create' CHECK (action IN ('create','update','delete')),
  target_id INTEGER REFERENCES memories(id) ON DELETE CASCADE,     -- update / delete 提议指向的记忆
  meta TEXT,
  use_count INTEGER NOT NULL DEFAULT 0,
  last_used_at TEXT,
  confirmed_at TEXT,
  expires_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_mem_user ON memories(user_id, status, scope, bot_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_mem_dedupe
  ON memories(user_id, scope, COALESCE(bot_id, 0), content_hash, action)
  WHERE status IN ('proposed','candidate','active');
"""


def migrate(c) -> int:
    """建基础表与 schema_meta，返回当前库版本（新库为 1）。"""
    c.executescript(SCHEMA)
    c.execute("CREATE TABLE IF NOT EXISTS schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
    ver = int((c.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone() or [1])[0])
    return ver
