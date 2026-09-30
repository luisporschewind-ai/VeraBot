"""安全（Security）：bcrypt 密码哈希 + JWT (HS256) 签发 / 校验。不涉及 HTTP 与数据库。"""
from datetime import datetime, timedelta, timezone

import bcrypt
import jwt

from .config import JWT_SECRET, TOKEN_TTL_HOURS

InvalidToken = jwt.PyJWTError


def hash_password(pw: str) -> str:
    return bcrypt.hashpw(pw.encode(), bcrypt.gensalt()).decode()


def verify_password(pw: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(pw.encode(), hashed.encode())
    except ValueError:
        return False


def issue_token(user_id: int, username: str) -> str:
    exp = datetime.now(timezone.utc) + timedelta(hours=TOKEN_TTL_HOURS)
    return jwt.encode({"sub": str(user_id), "name": username, "exp": exp}, JWT_SECRET, algorithm="HS256")


def decode_token(token: str) -> dict:
    """校验签名与过期时间；失败抛出 InvalidToken。"""
    return jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
