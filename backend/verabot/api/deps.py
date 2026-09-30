"""FastAPI 依赖（Dependencies）：当前用户、Bot 归属校验。"""
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .. import db
from ..core.security import InvalidToken, decode_token

bearer = HTTPBearer(auto_error=False)


def current_user(cred: HTTPAuthorizationCredentials | None = Depends(bearer)) -> dict:
    if cred is None:
        raise HTTPException(401, "未登录")
    try:
        payload = decode_token(cred.credentials)
    except InvalidToken:
        raise HTTPException(401, "登录已失效，请重新登录")
    with db.tx() as c:
        u = db.row(c.execute("SELECT id, username, created_at FROM users WHERE id=?", (int(payload["sub"]),)).fetchone())
    if not u:
        raise HTTPException(401, "用户不存在")
    return u


def require_bot(user: dict, bot_id: int) -> dict:
    b = db.get_bot(user["id"], bot_id)
    if not b:  # 他人的 Bot 与不存在的 Bot 统一返回 404，避免信息泄露
        raise HTTPException(404, "Bot 不存在")
    return b
