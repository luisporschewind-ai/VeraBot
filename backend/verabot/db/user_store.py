"""users 表的 SQL：公开资料、登录 / 注册、锁定计数、令牌版本、邮箱验证、头像时间戳。

业务规则（密码哈希、锁定策略、认领流程）留在 services；这里只放 SQL，调用方传入同一条连接以保持事务。
"""
from __future__ import annotations

from .database import row

# 公开资料用到的列（不含 password_hash）。services/users.py 以 USER_SQL 之名 re-export。
PUBLIC_USER_SQL = ("SELECT id, username, created_at, nickname, avatar_updated_at, email, email_verified_at, phone, "
                   "token_version FROM users WHERE id=?")
LOOKUP_COLUMNS = ("id", "username", "email", "phone")


def get_public(c, user_id: int) -> dict | None:
    return row(c.execute(PUBLIC_USER_SQL, (user_id,)).fetchone())


def set_nickname(c, user_id: int, nickname: str) -> None:
    c.execute("UPDATE users SET nickname=? WHERE id=?", (nickname, user_id))


def get_by(c, column: str, value) -> dict | None:
    """整行（含 password_hash）。column 只能是 LOOKUP_COLUMNS 之一。"""
    assert column in LOOKUP_COLUMNS
    return row(c.execute(f"SELECT * FROM users WHERE {column}=?", (value,)).fetchone())


def username_exists(c, username: str) -> bool:
    return bool(c.execute("SELECT 1 FROM users WHERE username=?", (username,)).fetchone())


def insert(c, *, username: str, password_hash: str, created_at: str, email: str | None,
           email_verified_at: str | None, phone: str | None) -> int:
    return c.execute(
        "INSERT INTO users(username, password_hash, created_at, email, email_verified_at, phone) VALUES (?,?,?,?,?,?)",
        (username, password_hash, created_at, email, email_verified_at, phone),
    ).lastrowid


def insert_username(c, username: str, password_hash: str, created_at: str) -> int:
    """老接口 {username, password} 注册。"""
    return c.execute("INSERT INTO users(username,password_hash,created_at) VALUES (?,?,?)",
                     (username, password_hash, created_at)).lastrowid


def set_login_failures(c, user_id: int, failures: int, locked_until: str | None) -> None:
    c.execute("UPDATE users SET failed_logins=?, locked_until=? WHERE id=?", (failures, locked_until, user_id))


def reset_login_failures(c, user_id: int) -> None:
    c.execute("UPDATE users SET failed_logins=0, locked_until=NULL WHERE id=?", (user_id,))


def bump_token_version(c, user_id: int) -> None:
    c.execute("UPDATE users SET token_version = token_version + 1 WHERE id=?", (user_id,))


def claim_email(c, user_id: int, now: str) -> None:
    """验证码认领未验证邮箱：清密码（空字符串不是合法 bcrypt）、标记已验证、令牌版本 +1。"""
    c.execute(
        "UPDATE users SET password_hash='', email_verified_at=?, token_version=token_version+1 WHERE id=?",
        (now, user_id),
    )


def set_email_verified(c, user_id: int, now: str) -> None:
    c.execute("UPDATE users SET email_verified_at=? WHERE id=?", (now, user_id))


def set_avatar_updated(c, user_id: int, updated_at: str) -> None:
    c.execute("UPDATE users SET avatar_updated_at=? WHERE id=?", (updated_at, user_id))


def clear_avatar_updated(c, user_id: int) -> None:
    c.execute("UPDATE users SET avatar_updated_at=NULL WHERE id=?", (user_id,))
