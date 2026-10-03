"""用户公开资料（Public profile）：昵称校验与对外字段。不返回 password_hash。"""
from .. import db
from ..db import user_store
from ..db.user_store import PUBLIC_USER_SQL as USER_SQL  # noqa: F401 — 旧名保留（SQL 在 db/user_store.py）

NICKNAME_MAX = 32


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
    email = u.get("email") or None
    phone = u.get("phone") or None
    return {
        "id": u["id"],
        "username": u["username"],
        "created_at": u.get("created_at"),
        "nickname": nick,
        # 没有昵称时：邮箱前缀 / 手机号后 4 位 / 用户名（邮箱、手机号账号的用户名是系统生成的，不展示）
        "display_name": nick or (email.split("@")[0] if email else None)
                        or (f"用户{phone[-4:]}" if phone else None) or u["username"],
        "email": email,
        "email_verified": bool(u.get("email_verified_at")) if email else False,
        "phone": phone,
        "has_avatar": bool(u.get("avatar_updated_at")),
        "avatar_updated_at": u.get("avatar_updated_at"),
    }


def load_public(user_id: int) -> dict | None:
    with db.tx() as c:
        u = user_store.get_public(c, user_id)
    return public_user(u)


def update_nickname(user_id: int, nickname: str) -> dict:
    with db.tx() as c:
        user_store.set_nickname(c, user_id, nickname)
        u = user_store.get_public(c, user_id)
    return public_user(u)
