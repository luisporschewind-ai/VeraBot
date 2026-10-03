"""安全（Security）：bcrypt 密码哈希 + JWT (HS256) 签发 / 校验。不涉及 HTTP 与数据库。"""
from datetime import datetime, timedelta, timezone

import hashlib
import hmac
import secrets

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


def issue_token(user_id: int, username: str, token_version: int = 0) -> str:
    """访问令牌（Access token）。`tv` = users.token_version；改密码 / 退出所有设备后旧令牌立即失效。"""
    exp = datetime.now(timezone.utc) + timedelta(hours=TOKEN_TTL_HOURS)
    return jwt.encode({"sub": str(user_id), "name": username, "tv": int(token_version or 0), "exp": exp,
                       "typ": "access"}, JWT_SECRET, algorithm="HS256")


def new_secret() -> str:
    """刷新令牌等不透明随机串（只把哈希存库）。"""
    return secrets.token_urlsafe(48)


def hash_secret(value: str) -> str:
    """刷新令牌 / 验证码的存库哈希（HMAC-SHA256，密钥同 JWT）。"""
    return hmac.new(JWT_SECRET.encode(), value.encode(), hashlib.sha256).hexdigest()


def decode_token(token: str) -> dict:
    """校验签名与过期时间；失败抛出 InvalidToken。"""
    return jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
