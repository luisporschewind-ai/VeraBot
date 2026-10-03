"""auth_refresh_tokens / auth_codes 表的 SQL（刷新令牌与邮箱验证码）。

签发 / 轮换 / 防枚举 / 错误次数等规则留在 services/auth.py；这里只放 SQL，调用方传入同一条连接以保持事务。
"""
from __future__ import annotations

from .database import row


# ---------- 刷新令牌 ----------
def insert_refresh(c, user_id: int, token_hash: str, expires_at: str, created_at: str) -> None:
    c.execute("INSERT INTO auth_refresh_tokens(user_id, token_hash, expires_at, created_at) VALUES (?,?,?,?)",
              (user_id, token_hash, expires_at, created_at))


def get_refresh(c, token_hash: str) -> dict | None:
    return row(c.execute("SELECT * FROM auth_refresh_tokens WHERE token_hash=?", (token_hash,)).fetchone())


def refresh_owner(c, token_hash: str):
    """→ sqlite3.Row(user_id) 或 None。"""
    return c.execute("SELECT user_id FROM auth_refresh_tokens WHERE token_hash=?", (token_hash,)).fetchone()


def revoke_refresh(c, refresh_id: int, now: str) -> None:
    c.execute("UPDATE auth_refresh_tokens SET revoked_at=? WHERE id=?", (now, refresh_id))


def revoke_refresh_by_hash(c, token_hash: str, now: str) -> None:
    c.execute("UPDATE auth_refresh_tokens SET revoked_at=? WHERE token_hash=? AND revoked_at IS NULL",
              (now, token_hash))


def revoke_user_refresh(c, user_id: int, now: str) -> None:
    """作废该用户全部未作废的刷新令牌。"""
    c.execute("UPDATE auth_refresh_tokens SET revoked_at=? WHERE user_id=? AND revoked_at IS NULL", (now, user_id))


# ---------- 邮箱验证码 ----------
def supersede_codes(c, email: str, purpose: str, now: str) -> None:
    """同一邮箱同一用途只保留最新的一条：旧码作废。"""
    c.execute("UPDATE auth_codes SET consumed_at=? WHERE email=? AND purpose=? AND consumed_at IS NULL",
              (now, email, purpose))


def insert_code(c, email: str, purpose: str, code_hash: str, expires_at: str, created_at: str) -> None:
    c.execute("INSERT INTO auth_codes(email, purpose, code_hash, expires_at, created_at) VALUES (?,?,?,?,?)",
              (email, purpose, code_hash, expires_at, created_at))


def latest_open_code(c, email: str, purpose: str) -> dict | None:
    return row(c.execute(
        "SELECT * FROM auth_codes WHERE email=? AND purpose=? AND consumed_at IS NULL ORDER BY id DESC LIMIT 1",
        (email, purpose)).fetchone())


def record_code_failure(c, code_id: int, attempts: int, consumed_at: str | None) -> None:
    c.execute("UPDATE auth_codes SET attempts=?, consumed_at=? WHERE id=?", (attempts, consumed_at, code_id))


def consume_code(c, code_id: int, now: str) -> None:
    c.execute("UPDATE auth_codes SET consumed_at=? WHERE id=?", (now, code_id))
