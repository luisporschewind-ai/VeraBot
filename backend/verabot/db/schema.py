"""表结构（Models / Schema）与幂等迁移（Migration v1 → v12）。"""
import json
import sqlite3
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

from ..core.config import DB_PATH, TIMEZONE
from .database import now_iso, tx

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


SCHEMA_VERSION = 12  # v11 = 提醒 R1，v12 = 图片附件

# v9：账号。邮箱存小写、手机号存 E.164；NULL 不参与唯一约束。
AUTH_SCHEMA = """
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users(email) WHERE email IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone ON users(phone) WHERE phone IS NOT NULL;
CREATE TABLE IF NOT EXISTS auth_codes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  email TEXT NOT NULL,
  purpose TEXT NOT NULL,                 -- login / verify
  code_hash TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  consumed_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_auth_codes_email ON auth_codes(email, purpose, id);
CREATE TABLE IF NOT EXISTS auth_refresh_tokens (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  expires_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  revoked_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_refresh_user ON auth_refresh_tokens(user_id);
"""

# v7：MCP 服务器与工具缓存。与 docs/design/MCP_CAPABILITY.md §12.2 同一次迁移。
# 凭据 / oauth_states / pending_actions 先建表，OAuth 与确认卡片在后续里程碑使用。
MCP_SCHEMA = """
CREATE TABLE IF NOT EXISTS mcp_servers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  slug TEXT NOT NULL,
  source TEXT NOT NULL,
  catalog_id TEXT,
  name TEXT NOT NULL,
  transport TEXT NOT NULL,
  url TEXT,
  trust TEXT NOT NULL,
  auth_type TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'needs_auth',
  account_label TEXT,
  granted_scopes TEXT,
  discover_json TEXT,
  last_synced_at TEXT, last_error TEXT,
  consent_at TEXT,                                          -- D4：同意把该服务的工具结果发给 DeepSeek 的时间；NULL = 未同意
  sync_status TEXT NOT NULL DEFAULT 'pending',              -- pending / syncing / ok / error
  circuit_failures INTEGER NOT NULL DEFAULT 0,              -- 连续传输失败次数（不含工具级 isError / 4xx）
  circuit_open_until TEXT,                                  -- 熔断打开到期时间；NULL = 关闭
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
  UNIQUE(user_id, slug)
);
CREATE TABLE IF NOT EXISTS mcp_credentials (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  server_id INTEGER REFERENCES mcp_servers(id) ON DELETE CASCADE,
  provider TEXT,
  issuer TEXT NOT NULL,
  client_info_enc BLOB,
  refresh_token_enc BLOB,
  access_token_enc BLOB,
  expires_at TEXT, scopes TEXT,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
  UNIQUE(user_id, server_id, issuer)
);
CREATE TABLE IF NOT EXISTS mcp_tools (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  server_id INTEGER NOT NULL REFERENCES mcp_servers(id) ON DELETE CASCADE,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  mcp_name TEXT NOT NULL,
  full_name TEXT NOT NULL,
  title TEXT, description TEXT NOT NULL,
  input_schema TEXT NOT NULL, output_schema TEXT, annotations TEXT,
  def_hash TEXT NOT NULL,
  accepted_hash TEXT,
  risk TEXT NOT NULL,
  confirm_policy TEXT NOT NULL DEFAULT 'default',
  status TEXT NOT NULL DEFAULT 'active',
  first_seen_at TEXT NOT NULL, last_seen_at TEXT NOT NULL,
  UNIQUE(server_id, mcp_name), UNIQUE(user_id, full_name)
);
CREATE TABLE IF NOT EXISTS oauth_states (
  state TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  server_id INTEGER REFERENCES mcp_servers(id) ON DELETE CASCADE,
  provider TEXT,
  payload_enc BLOB NOT NULL,
  expires_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS pending_actions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  bot_id INTEGER REFERENCES bots(id) ON DELETE SET NULL,
  kind TEXT NOT NULL,
  server_id INTEGER REFERENCES mcp_servers(id) ON DELETE CASCADE,
  tool_full_name TEXT,
  payload_enc BLOB NOT NULL,
  payload_hash TEXT NOT NULL, tool_def_hash TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  result TEXT,
  created_at TEXT NOT NULL, expires_at TEXT NOT NULL, decided_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_pending_user ON pending_actions(user_id, status);
CREATE INDEX IF NOT EXISTS idx_mcp_tools_user ON mcp_tools(user_id, status);
"""

# v10：插件安装关系。启用、同意、同步、熔断仍在 mcp_servers。
# 不预装任何插件。迁移只把「用过」的目录服务记为 installed，不为没用过的行写 uninstalled 墓碑。
PLUGIN_SCHEMA = """
CREATE TABLE IF NOT EXISTS user_plugins (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  plugin_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'installed',
  catalog_version TEXT,
  settings TEXT,
  installed_at TEXT, uninstalled_at TEXT,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
  UNIQUE(user_id, plugin_id)
);
CREATE INDEX IF NOT EXISTS idx_user_plugins_user ON user_plugins(user_id, status);
"""

# v11：提醒状态机 + 通用通知层。推送相关表一次建好，之后的分期只加代码。
REMINDER_SCHEMA = """
CREATE TABLE IF NOT EXISTS reminder_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reminder_id INTEGER NOT NULL REFERENCES reminders(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  from_status TEXT, to_status TEXT,
  occurrence_due_utc TEXT,
  actor TEXT NOT NULL,
  actor_bot_id INTEGER,
  client TEXT,
  detail TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_rev_rem ON reminder_events(user_id, reminder_id, id);
CREATE TABLE IF NOT EXISTS notifications (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  category TEXT NOT NULL CHECK (category IN ('reminder','bot_message','delegation','plugin','system')),
  title TEXT NOT NULL, body TEXT, sensitive INTEGER NOT NULL DEFAULT 0,
  bot_id INTEGER REFERENCES bots(id) ON DELETE SET NULL,
  reminder_id INTEGER REFERENCES reminders(id) ON DELETE SET NULL,
  message_id INTEGER REFERENCES messages(id) ON DELETE SET NULL,
  plugin_id TEXT, link TEXT, thread_id TEXT,
  dedupe_key TEXT NOT NULL,
  created_at TEXT NOT NULL, read_at TEXT, opened_at TEXT, expires_at TEXT,
  UNIQUE(user_id, dedupe_key)
);
CREATE INDEX IF NOT EXISTS idx_ntf_user ON notifications(user_id, read_at, id);
CREATE TABLE IF NOT EXISTS notification_deliveries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  notification_id INTEGER NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  channel TEXT NOT NULL CHECK (channel IN ('inbox','local','apns')),
  device_id TEXT,
  state TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT, apns_id TEXT,
  scheduled_for TEXT, sent_at TEXT, delivered_at TEXT, opened_at TEXT, updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_ndl_state ON notification_deliveries(state, scheduled_for);
CREATE TABLE IF NOT EXISTS notification_prefs (
  user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  enabled INTEGER NOT NULL DEFAULT 1,
  categories TEXT NOT NULL DEFAULT '{}',
  muted_bots TEXT NOT NULL DEFAULT '[]',
  quiet_enabled INTEGER NOT NULL DEFAULT 0,
  quiet_start TEXT NOT NULL DEFAULT '23:00', quiet_end TEXT NOT NULL DEFAULT '08:00',
  quiet_timezone TEXT NOT NULL DEFAULT 'Asia/Shanghai',
  preview TEXT NOT NULL DEFAULT 'title',
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS push_devices (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL,
  platform TEXT NOT NULL DEFAULT 'ios',
  apns_token TEXT,
  apns_env TEXT,
  app_version TEXT, os_version TEXT, timezone TEXT,
  local_reminders INTEGER NOT NULL DEFAULT 1,
  disabled_at TEXT, last_seen_at TEXT NOT NULL, created_at TEXT NOT NULL,
  UNIQUE(user_id, device_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_push_token ON push_devices(apns_token) WHERE apns_token IS NOT NULL;
CREATE TABLE IF NOT EXISTS idempotency_keys (
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  key TEXT NOT NULL,
  status_code INTEGER NOT NULL,
  body TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (user_id, key)
);
CREATE INDEX IF NOT EXISTS idx_rem_user_status ON reminders(user_id, status, due_utc);
CREATE INDEX IF NOT EXISTS idx_rem_assignee ON reminders(user_id, assignee_bot_id);
"""
ALL_TOOLS_V2 = ["get_weather", "create_reminder", "list_reminders", "ask_bot"]


def _backup_before_v11() -> None:
    """已有库升到 v11 之前复制一份。新文件还没有 schema_meta 时不备份。"""
    path = Path(DB_PATH)
    if not path.is_file():
        return
    try:
        src = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    except sqlite3.Error:
        return
    try:
        row = src.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()
    except sqlite3.Error:
        return
    finally:
        src.close()
    if not row or int(row[0]) >= 11:
        return
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    dest = path.with_name(f"{path.name}.bak-before-v11-{stamp}")
    if dest.exists():
        dest = path.with_name(f"{path.name}.bak-before-v11-{stamp}-{datetime.now().microsecond}")
    src = sqlite3.connect(path)
    dst = sqlite3.connect(dest)
    try:
        src.backup(dst)
    finally:
        dst.close()
        src.close()


def _legacy_due(text: str | None):
    if text is None or not str(text).strip():
        return None
    raw = str(text).strip().replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(raw)
    except ValueError:
        return "invalid"
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=ZoneInfo(TIMEZONE))
    return parsed


def _backfill_reminders(c, now: datetime) -> None:
    rows = c.execute("SELECT id, user_id, bot_id, content, due_at, done, created_at FROM reminders").fetchall()
    for row in rows:
        content = row[3] or ""
        title = content[:200]
        note = content[200:] or None
        parsed = _legacy_due(row[4])
        due_at = due_utc = None
        if parsed == "invalid":
            extra = f"原时间：{row[4]}"
            note = f"{note}\n{extra}" if note else extra
        elif parsed is not None:
            local = parsed.astimezone(ZoneInfo(TIMEZONE)).replace(second=0, microsecond=0)
            due_at = local.isoformat(timespec="minutes")
            due_utc = local.astimezone(timezone.utc).isoformat(timespec="seconds")
        if row[5]:
            status, completed = "done", None
        elif parsed is None or parsed == "invalid":
            status, completed = "scheduled", None
        elif parsed > now:
            status, completed = "scheduled", None
        elif now - parsed <= timedelta(hours=24):
            status, completed = "due", None
        else:
            status, completed = "missed", None
        c.execute(
            """UPDATE reminders SET title=?, note=?, content=?, due_at=?, due_utc=?, timezone=?, all_day=0,
               occurrence_index=1, status=?, priority=0, created_by='bot', assignee_bot_id=?,
               notify=?, alert_offsets='[0]', version=1, completed_at=?, updated_at=?, done=?
               WHERE id=?""",
            (title, note, title, due_at, due_utc, TIMEZONE, status, row[2],
             0 if due_at is None else 1, completed, row[6], 1 if status == "done" else 0, row[0]),
        )
        c.execute(
            """INSERT INTO reminder_events(user_id, reminder_id, kind, to_status, actor, client, detail, created_at)
               VALUES (?,?, 'created', ?, 'system', 'scheduler', ?, ?)""",
            (row[1], row[0], status, json.dumps({"migrated": True}, ensure_ascii=False), row[6] or now_iso()),
        )


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
    v5 → v6：bots.pinned_at（UTC ISO 8601，NULL = 未置顶）。
    v6 → v7：MCP 表（mcp_servers / mcp_tools 等）。不改 allowed_tools，不给存量 Bot 授予 MCP 工具。
    v7 → v8：MCP 同意时间、同步状态、熔断计数。不改工具定义、白名单或已有服务器行的身份字段。
    v8 → v9：账号邮箱 / 手机号（部分唯一索引）、邮箱验证时间、token_version、登录失败锁定；
             新表 auth_codes（邮箱验证码，只存哈希）、auth_refresh_tokens（刷新令牌，只存哈希）。
             不改用户名、密码哈希和任何业务数据；demo 等老账号继续用用户名登录。
    v9 → v10：user_plugins（安装关系）+ mcp_servers.plugin_id。不预装。
             用过（已同意、已同步，或任一 Bot 白名单含该服务工具）的目录服务记为 installed；
             没用过的不写 uninstalled 墓碑。不改 consent_at、工具缓存和 allowed_tools。
             演示账号的 Learn 若已同意，会作为「用过」保留为已安装。
    v10 → v11：提醒补列（状态、时区、重复、归属）并回填；新建 reminder_events、notifications、
             notification_deliveries、notification_prefs、push_devices、idempotency_keys。
             不改其他表的数据。迁移前备份 verabot.db.bak-before-v11-<时间戳>。
    v11 → v12：attachments 表（图片元数据；文件在 DATA_DIR/attachments）。v11 是提醒 R1。
    """
    _backup_before_v11()
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
        # --- v6：Bot 置顶。NULL 表示未置顶，不回填其他数据 ---
        _add_column(c, "bots", "pinned_at", "TEXT")
        # --- v7：MCP。只建表，不回填、不改写任何 Bot 的 allowed_tools ---
        c.executescript(MCP_SCHEMA)
        # --- v8：同意 / 异步同步 / 熔断。已有 v7 表用 ALTER 补列（CREATE IF NOT EXISTS 不会改旧表） ---
        _add_column(c, "mcp_servers", "consent_at", "TEXT")
        _add_column(c, "mcp_servers", "sync_status", "TEXT NOT NULL DEFAULT 'pending'")
        _add_column(c, "mcp_servers", "circuit_failures", "INTEGER NOT NULL DEFAULT 0")
        _add_column(c, "mcp_servers", "circuit_open_until", "TEXT")
        if ver < 8:
            # 已经同步成功的行标成 ok，避免升级后再次被当成「还没同步」而去连外网。
            # 同意时间留空：M1 没有记录，必须由用户重新同意后才能调用工具。
            c.execute(
                """UPDATE mcp_servers SET sync_status='ok'
                   WHERE sync_status='pending' AND status='connected' AND last_synced_at IS NOT NULL"""
            )
            c.execute(
                """UPDATE mcp_servers SET sync_status='error'
                   WHERE sync_status='pending' AND status='error'"""
            )
        # --- v9：账号体系（邮箱 / 手机号 / 刷新令牌）。只加列和新表 ---
        _add_column(c, "users", "email", "TEXT")
        _add_column(c, "users", "email_verified_at", "TEXT")
        _add_column(c, "users", "phone", "TEXT")
        _add_column(c, "users", "token_version", "INTEGER NOT NULL DEFAULT 0")
        _add_column(c, "users", "failed_logins", "INTEGER NOT NULL DEFAULT 0")
        _add_column(c, "users", "locked_until", "TEXT")
        c.executescript(AUTH_SCHEMA)
        # --- v10：插件。只加安装表和关联列；不预装，不为未使用的目录行写墓碑 ---
        _add_column(c, "mcp_servers", "plugin_id", "TEXT")
        c.executescript(PLUGIN_SCHEMA)
        if ver < 10:
            now = now_iso()
            c.execute(
                """UPDATE mcp_servers SET plugin_id = catalog_id
                   WHERE plugin_id IS NULL AND source='catalog'
                     AND catalog_id IS NOT NULL"""
            )
            # 用过 = 同意过、同步过，或某个 Bot 的白名单里已经有 mcp__{slug}__。
            # 目录自动补出来、但用户没碰过的行（包括默认开启却从未同意的 Learn）保持未安装，
            # 且不插入 status='uninstalled'。墓碑只留给用户以后主动卸载，避免挡住预装。
            c.execute(
                """INSERT OR IGNORE INTO user_plugins(
                       user_id, plugin_id, status, installed_at, created_at, updated_at)
                   SELECT s.user_id, s.plugin_id, 'installed', s.created_at, s.created_at, ?
                   FROM mcp_servers s
                   WHERE s.plugin_id IS NOT NULL AND (
                     s.consent_at IS NOT NULL
                     OR s.last_synced_at IS NOT NULL
                     OR EXISTS (
                       SELECT 1 FROM bots b
                       WHERE b.user_id = s.user_id
                         AND instr(b.allowed_tools, 'mcp__' || s.slug || '__') > 0
                     )
                   )""",
                (now,),
            )
        # --- v11：提醒状态机与通知层。列和表每次都补；回填只在第一次从旧版本升上来时做 ---
        for name, ddl in (
            ("title", "TEXT"),
            ("note", "TEXT"),
            ("timezone", "TEXT NOT NULL DEFAULT 'Asia/Shanghai'"),
            ("due_utc", "TEXT"),
            ("all_day", "INTEGER NOT NULL DEFAULT 0"),
            ("rrule", "TEXT"),
            ("occurrence_index", "INTEGER NOT NULL DEFAULT 1"),
            ("status", "TEXT NOT NULL DEFAULT 'scheduled'"),
            ("snoozed_until", "TEXT"),
            ("priority", "INTEGER NOT NULL DEFAULT 0"),
            ("created_by", "TEXT NOT NULL DEFAULT 'user'"),
            ("assignee_bot_id", "INTEGER"),
            ("source_message_id", "INTEGER"),
            ("client", "TEXT"),
            ("notify", "INTEGER NOT NULL DEFAULT 1"),
            ("alert_offsets", "TEXT NOT NULL DEFAULT '[0]'"),
            ("version", "INTEGER NOT NULL DEFAULT 1"),
            ("completed_at", "TEXT"),
            ("cancelled_at", "TEXT"),
            ("updated_at", "TEXT"),
        ):
            _add_column(c, "reminders", name, ddl)
        c.executescript(REMINDER_SCHEMA)
        # v10 旧表没有 bot_id 外键，只靠 ON DELETE SET NULL 覆盖不了已有库。每次启动重建触发器。
        c.execute("DROP TRIGGER IF EXISTS reminders_clear_assignee")
        c.execute("""CREATE TRIGGER reminders_clear_assignee
            AFTER DELETE ON bots
            FOR EACH ROW
            BEGIN
              UPDATE reminders SET bot_id=NULL WHERE bot_id=OLD.id;
              UPDATE reminders SET assignee_bot_id=NULL WHERE assignee_bot_id=OLD.id;
            END""")
        c.execute("""CREATE TRIGGER IF NOT EXISTS reminders_clear_message
            AFTER DELETE ON messages
            FOR EACH ROW
            BEGIN
              UPDATE reminders SET source_message_id=NULL WHERE source_message_id=OLD.id;
            END""")
        if ver < 11:
            _backfill_reminders(c, datetime.now(timezone.utc))
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
        # --- v12：图片附件（在 v11 提醒 R1 之后）。只建表 ---
        from .attachment_schema import migrate_attachments
        migrate_attachments(c)
        if ver < SCHEMA_VERSION:
            c.execute("INSERT OR REPLACE INTO schema_meta(key,value) VALUES ('version', ?)", (str(SCHEMA_VERSION),))
