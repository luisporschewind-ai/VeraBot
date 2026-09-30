"""账号（Auth）：注册 / 登录 / 当前用户。"""
import re

from fastapi import APIRouter, Depends, HTTPException

from ... import db
from ...core.security import hash_password, issue_token, verify_password
from ..deps import current_user
from ..schemas import Credentials

router = APIRouter(tags=["auth"])


@router.post("/api/auth/register")
def register(body: Credentials):
    if not re.fullmatch(r"[A-Za-z0-9_\-\u4e00-\u9fa5]+", body.username):
        raise HTTPException(400, "用户名仅支持中英文、数字、下划线和短横线")
    with db.tx() as c:
        if c.execute("SELECT 1 FROM users WHERE username=?", (body.username,)).fetchone():
            raise HTTPException(409, "用户名已存在")
        uid = c.execute("INSERT INTO users(username,password_hash,created_at) VALUES (?,?,?)",
                        (body.username, hash_password(body.password), db.now_iso())).lastrowid
    return {"token": issue_token(uid, body.username), "user": {"id": uid, "username": body.username}}


@router.post("/api/auth/login")
def login(body: Credentials):
    with db.tx() as c:
        u = db.row(c.execute("SELECT * FROM users WHERE username=?", (body.username,)).fetchone())
    if not u or not verify_password(body.password, u["password_hash"]):
        raise HTTPException(401, "用户名或密码错误")
    return {"token": issue_token(u["id"], u["username"]), "user": {"id": u["id"], "username": u["username"]}}


@router.get("/api/me")
def me(user=Depends(current_user)):
    return user
