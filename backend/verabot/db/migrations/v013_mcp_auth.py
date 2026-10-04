"""v12 → v13：需授权 MCP 连接器（MCP_AUTH_CONNECTORS_PLAN v1.0 §5.5）。

只加列 / 建表，不改已有行、不改 Bot 白名单。mcp_credentials 在 v7 已建表但一直为空。
令牌密文用 core.crypto 的 token 密钥（VERABOT_TOKEN_ENC_KEY / data/.token_key）。
"""
from ._util import _add_column

OAUTH_CLIENTS_SCHEMA = """
CREATE TABLE IF NOT EXISTS mcp_oauth_clients (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  issuer TEXT NOT NULL,
  redirect_uri TEXT NOT NULL,
  client_id TEXT NOT NULL,
  client_secret_enc TEXT,
  registration_enc TEXT,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
  UNIQUE(issuer, redirect_uri)
);
"""


def migrate(c, ver: int) -> None:
    _add_column(c, "mcp_credentials", "kind", "TEXT NOT NULL DEFAULT 'oauth'")   # static_bearer / oauth
    _add_column(c, "mcp_credentials", "token_hint", "TEXT")                       # 末 4 位，仅展示
    _add_column(c, "mcp_credentials", "last_verified_at", "TEXT")
    _add_column(c, "mcp_servers", "auth_error", "TEXT")   # token_invalid / expired / insufficient_scope / network_unreachable
    c.executescript(OAUTH_CLIENTS_SCHEMA)
