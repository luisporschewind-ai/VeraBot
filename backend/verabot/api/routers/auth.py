"""账号（Auth）：注册 / 登录 / 当前用户。"""
import re

from fastapi import APIRouter, Depends, HTTPException

from ... import db
from ...core.security import hash_password, issue_token, verify_password
from ...services.users import public_user, update_nickname
from ..deps import current_user
from ..schemas import Credentials, NicknameIn

router = APIRouter(tags=["auth"])


@router.post("/api/auth/register")
def register(body: Credentials):
    if not re.fullmatch(r"[A-Za-z0-9_\-\u4e00-\u9fa5]+", body.username):
        raise HTTPException(400, "用户名仅支持中英文、数字、下划线和短横线")
    with db.tx() as c:
        if c.execute("SELECT 1 FROM users WHERE username=?", (body.username,)).fetchone():
            raise HTTPException(409, "用户名已存在")
        created = db.now_iso()
        uid = c.execute("INSERT INTO users(username,password_hash,created_at) VALUES (?,?,?)",
                        (body.username, hash_password(body.password), created)).lastrowid
    user = public_user({"id": uid, "username": body.username, "created_at": created,
                        "nickname": None, "avatar_updated_at": None})
    return {"token": issue_token(uid, body.username), "user": user}


@router.post("/api/auth/login")
def login(body: Credentials):
    with db.tx() as c:
        u = db.row(c.execute("SELECT * FROM users WHERE username=?", (body.username,)).fetchone())
    if not u or not verify_password(body.password, u["password_hash"]):
        raise HTTPException(401, "用户名或密码错误")
    return {"token": issue_token(u["id"], u["username"]), "user": public_user(u)}


@router.get("/api/me")
def me(user=Depends(current_user)):
    return user


@router.patch("/api/me")
def patch_me(body: NicknameIn, user=Depends(current_user)):
    """修改当前用户昵称。用户名不可改；空白 / 超长返回 422。"""
    return update_nickname(user["id"], body.nickname)
