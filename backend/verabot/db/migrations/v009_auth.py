"""v8 → v9：账号邮箱 / 手机号（部分唯一索引）、邮箱验证时间、token_version、登录失败锁定；
auth_codes（邮箱验证码，只存哈希）、auth_refresh_tokens（刷新令牌，只存哈希）。"""
from ._util import _add_column

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


def migrate(c, ver: int) -> None:
    # --- v9：账号体系（邮箱 / 手机号 / 刷新令牌）。只加列和新表 ---
    _add_column(c, "users", "email", "TEXT")
    _add_column(c, "users", "email_verified_at", "TEXT")
    _add_column(c, "users", "phone", "TEXT")
    _add_column(c, "users", "token_version", "INTEGER NOT NULL DEFAULT 0")
    _add_column(c, "users", "failed_logins", "INTEGER NOT NULL DEFAULT 0")
    _add_column(c, "users", "locked_until", "TEXT")
    c.executescript(AUTH_SCHEMA)
