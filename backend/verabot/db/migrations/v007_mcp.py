"""v6 → v7：MCP 表（mcp_servers / mcp_tools 等）。不改 allowed_tools，不给存量 Bot 授予 MCP 工具。"""

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


def migrate(c, ver: int) -> None:
    # --- v7：MCP。只建表，不回填、不改写任何 Bot 的 allowed_tools ---
    c.executescript(MCP_SCHEMA)
