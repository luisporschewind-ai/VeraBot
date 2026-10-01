"""表结构（Models / Schema）与幂等迁移（Migration v1 → v3）。"""
import json

from .database import tx

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
"""


SCHEMA_VERSION = 3
ALL_TOOLS_V2 = ["get_weather", "create_reminder", "list_reminders", "ask_bot"]


def _columns(c, table: str) -> set[str]:
    return {r[1] for r in c.execute(f"PRAGMA table_info({table})").fetchall()}


def _add_column(c, table: str, name: str, ddl: str):
    if name not in _columns(c, table):
        c.execute(f"ALTER TABLE {table} ADD COLUMN {name} {ddl}")


def init_db():
    """建表 + 幂等迁移（Idempotent migration）。

    v1 → v2：多 Agent 权限模型 / 协作审计 / 用户预算。
    v2 → v3：用户昵称、用户头像、Bot 照片头像（表情符号字段保持不变）。
    """
    with tx() as c:
        c.executescript(SCHEMA)
        c.execute("CREATE TABLE IF NOT EXISTS schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        ver = int((c.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone() or [1])[0])
        # --- bots：权限字段。列默认值 = 最小权限（Least privilege） ---
        _add_column(c, "bots", "allowed_tools", "TEXT NOT NULL DEFAULT '[]'")        # 工具白名单 Tool allowlist
        _add_column(c, "bots", "delegate_to", "TEXT NOT NULL DEFAULT '[]'")          # 可委派目标 Bot id 白名单
        _add_column(c, "bots", "accept_delegation", "INTEGER NOT NULL DEFAULT 0")    # 是否接受其他 Bot 委派
        # --- users：个人 Token 预算覆盖（NULL = 使用全局 DAILY_TOKEN_QUOTA） ---
        _add_column(c, "users", "token_budget", "INTEGER")
        # --- delegations：完整协作审计字段 ---
        for name, ddl in [("status", "TEXT NOT NULL DEFAULT 'ok'"), ("reason", "TEXT"), ("depth", "INTEGER NOT NULL DEFAULT 1"),
                          ("payload", "TEXT"), ("shared_truncated", "INTEGER NOT NULL DEFAULT 0"),
                          ("prompt_tokens", "INTEGER NOT NULL DEFAULT 0"), ("completion_tokens", "INTEGER NOT NULL DEFAULT 0"),
                          ("total_tokens", "INTEGER NOT NULL DEFAULT 0")]:
            _add_column(c, "delegations", name, ddl)
        c.execute("""CREATE TABLE IF NOT EXISTS audit_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            bot_id INTEGER, kind TEXT NOT NULL, detail TEXT, created_at TEXT NOT NULL)""")
        c.execute("CREATE INDEX IF NOT EXISTS idx_deleg_user ON delegations(user_id, id)")
        if ver < 2:
            # 存量 Bot（v0.1 中本就拥有全部工具、可互相委派）：授予等价权限，保证 demo 行为不变
            for (uid,) in c.execute("SELECT DISTINCT user_id FROM bots").fetchall():
                ids = [r[0] for r in c.execute("SELECT id FROM bots WHERE user_id=? ORDER BY id", (uid,)).fetchall()]
                for bid in ids:
                    c.execute("UPDATE bots SET allowed_tools=?, delegate_to=?, accept_delegation=1 WHERE id=?",
                              (json.dumps(ALL_TOOLS_V2), json.dumps([x for x in ids if x != bid]), bid))
            # 历史委派记录：孤儿清理（被删除 Bot 的记录）
            c.execute("DELETE FROM delegations WHERE from_bot_id NOT IN (SELECT id FROM bots) "
                      "OR to_bot_id NOT IN (SELECT id FROM bots)")
        # --- v3：昵称与照片头像。NULL = 未设置（昵称回退用户名；头像回退首字母 / 表情） ---
        _add_column(c, "users", "nickname", "TEXT")
        _add_column(c, "users", "avatar_updated_at", "TEXT")
        _add_column(c, "bots", "image_updated_at", "TEXT")
        if ver < SCHEMA_VERSION:
            c.execute("INSERT OR REPLACE INTO schema_meta(key,value) VALUES ('version', ?)", (str(SCHEMA_VERSION),))
