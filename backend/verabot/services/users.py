"""用户公开资料（Public profile）：昵称校验与对外字段。不返回 password_hash。"""
from .. import db

NICKNAME_MAX = 32
USER_SQL = "SELECT id, username, created_at, nickname, avatar_updated_at FROM users WHERE id=?"


def clean_nickname(value: str) -> str:
    """去首尾空白后校验：非空、最多 32 个字、不含控制字符。"""
    if not isinstance(value, str):
        raise ValueError("昵称不能为空")
    if len(value) > 64:
        raise ValueError(f"昵称最多 {NICKNAME_MAX} 个字")
    v = value.strip()
    if not v:
        raise ValueError("昵称不能为空")
    if len(v) > NICKNAME_MAX:
        raise ValueError(f"昵称最多 {NICKNAME_MAX} 个字")
    if any(ord(ch) < 32 or ord(ch) == 127 for ch in v):
        raise ValueError("昵称不能包含控制字符")
    return v


def public_user(u: dict | None) -> dict | None:
    if not u:
        return None
    nick = u.get("nickname")
    if isinstance(nick, str):
        nick = nick.strip() or None
    else:
        nick = None
    return {
        "id": u["id"],
        "username": u["username"],
        "created_at": u.get("created_at"),
        "nickname": nick,
        "display_name": nick or u["username"],
        "has_avatar": bool(u.get("avatar_updated_at")),
        "avatar_updated_at": u.get("avatar_updated_at"),
    }


def load_public(user_id: int) -> dict | None:
    with db.tx() as c:
        u = db.row(c.execute(USER_SQL, (user_id,)).fetchone())
    return public_user(u)


def update_nickname(user_id: int, nickname: str) -> dict:
    with db.tx() as c:
        c.execute("UPDATE users SET nickname=? WHERE id=?", (nickname, user_id))
        u = db.row(c.execute(USER_SQL, (user_id,)).fetchone())
    return public_user(u)
