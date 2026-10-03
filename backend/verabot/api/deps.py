"""FastAPI 依赖（Dependencies）：当前用户、Bot 归属校验。"""
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from ..core.security import InvalidToken, decode_token
from ..services.users import public_user
from .. import db
from ..db import user_store

bearer = HTTPBearer(auto_error=False)


def current_user(cred: HTTPAuthorizationCredentials | None = Depends(bearer)) -> dict:
    if cred is None:
        raise HTTPException(401, "未登录")
    try:
        payload = decode_token(cred.credentials)
    except InvalidToken:
        raise HTTPException(401, "登录已失效，请重新登录")
    with db.tx() as c:
        u = user_store.get_public(c, int(payload["sub"]))
    if not u:
        raise HTTPException(401, "用户不存在")
    if payload.get("typ", "access") != "access" or int(payload.get("tv", 0)) != int(u.get("token_version") or 0):
        raise HTTPException(401, "登录已失效，请重新登录")
    return public_user(u)


def require_bot(user: dict, bot_id: int) -> dict:
    b = db.get_bot(user["id"], bot_id)
    if not b:  # 他人的 Bot 与不存在的 Bot 统一返回 404，避免信息泄露
        raise HTTPException(404, "Bot 不存在")
    return b
