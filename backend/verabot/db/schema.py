"""表结构（Models / Schema）与幂等迁移（Migration v1 → v5）。"""
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


SCHEMA_VERSION = 5
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
    v3 → v4：长期记忆 memories 表 + bots.memory_access / users.memory_enabled / messages.memory_ids。
    v4 → v5：bots.tags（JSON 数组，默认 []）。不改权限、记忆、头像。
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
        # --- v4：记忆（Memory）。Boss 决策（2026-10-01）：默认开启——新 Bot 与存量 Bot 都是 bot_and_global，
        #     用户总开关默认开。迁移不写入任何记忆，不改动 allowed_tools / delegate_to ---
        _add_column(c, "bots", "memory_access", "TEXT NOT NULL DEFAULT 'bot_and_global'")  # none / bot / bot_and_global
        _add_column(c, "users", "memory_enabled", "INTEGER NOT NULL DEFAULT 1")             # 用户总开关
        _add_column(c, "messages", "memory_ids", "TEXT")                                    # 本条回复注入了哪些记忆（JSON list）
        # --- v5：Bot 标签。JSON 字符串数组，默认 []。不回填、不改写已有权限 / 记忆 / 头像 ---
        _add_column(c, "bots", "tags", "TEXT NOT NULL DEFAULT '[]'")
        # 标签上限收紧 (2026-10-01：最多 3 个、每个 4 字)。结构不变 (仍是 v5)；每次启动把超限的存量标签收敛：
        # 保留前 3 个、每个截断到 4 字、去重。幂等，只改写确实变化的行。
        from ..core.tags import coerce_stored_tags
        for bid, raw in c.execute("SELECT id, tags FROM bots WHERE tags != '[]'").fetchall():
            try:
                old = json.loads(raw or "[]")
            except ValueError:
                old = None
            new = coerce_stored_tags(old)
            if new != old:
                c.execute("UPDATE bots SET tags=? WHERE id=?", (json.dumps(new, ensure_ascii=False), bid))
        if ver < SCHEMA_VERSION:
            c.execute("INSERT OR REPLACE INTO schema_meta(key,value) VALUES ('version', ?)", (str(SCHEMA_VERSION),))
