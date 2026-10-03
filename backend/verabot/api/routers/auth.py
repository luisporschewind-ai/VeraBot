"""账号（Auth）：注册 / 登录 / 刷新令牌 / 邮箱验证码 / 当前用户。逻辑在 services/auth.py。

- 新：邮箱 + 密码、手机号 + 密码、邮箱 + 验证码（schema v9，见 docs/design/AUTH_REFACTOR.md）。
- 旧：{username, password} 注册 / 登录继续可用（demo 账号、测试脚本、冻结的 Web）。
"""
import os
import re

from fastapi import APIRouter, Depends, HTTPException, Request

from ...core import ratelimit
from ...services import auth as svc
from ...services.users import update_nickname
from ..deps import current_user
from ..schemas import EmailCodeLoginIn, EmailCodeSendIn, EmailVerifyIn, LoginIn, NicknameIn, RefreshIn, RegisterIn

router = APIRouter(tags=["auth"])

IP_WINDOW = 600


def _ip_limit() -> int:
    return int(os.getenv("VERABOT_AUTH_IP_LIMIT", "30"))   # 同一 IP 10 分钟内注册 + 登录失败的上限


def _ip(request: Request) -> str:
    return request.client.host if request.client else "unknown"


def _raise(e: svc.AuthError):
    raise HTTPException(e.status, {"message": e.message, "code": e.code} if e.status != 401 else e.message)


def _guard_ip(key: str):
    if ratelimit.count(key, IP_WINDOW) >= _ip_limit():
        raise HTTPException(429, {"message": "尝试次数过多，请稍后再试", "code": "rate_limited"})


@router.post("/api/auth/register")
def register(body: RegisterIn, request: Request):
    key = f"auth-ip:{_ip(request)}"
    _guard_ip(key)
    ratelimit.hit(key, 10**6, IP_WINDOW)
    try:
        if body.username is not None:
            if not re.fullmatch(r"[A-Za-z0-9_\-\u4e00-\u9fa5]+", body.username) or not (3 <= len(body.username) <= 32):
                raise HTTPException(400, "用户名仅支持中英文、数字、下划线和短横线")
            if len(body.password) < 6:
                raise HTTPException(422, "密码至少 6 位")
            return svc.register_username(body.username, body.password)
        return svc.register(email=body.email, phone=body.phone, password=body.password)
    except svc.AuthError as e:
        if e.code == "username_taken":
            raise HTTPException(409, e.message)
        _raise(e)


@router.post("/api/auth/login")
def login(body: LoginIn, request: Request):
    key = f"auth-ip:{_ip(request)}"
    _guard_ip(key)
    identifier = body.identifier if body.identifier is not None else body.username
    if not identifier:
        raise HTTPException(422, "请输入账号")
    try:
        return svc.login(identifier, body.password)
    except svc.AuthError as e:
        if e.status == 401:
            ratelimit.hit(key, 10**6, IP_WINDOW)
            # 旧客户端（Web / 脚本）沿用原文案
            raise HTTPException(401, "用户名或密码错误" if body.identifier is None else svc.GENERIC_LOGIN_ERROR)
        _raise(e)


@router.post("/api/auth/refresh")
def refresh(body: RefreshIn):
    try:
        return svc.refresh(body.refresh_token)
    except svc.AuthError as e:
        _raise(e)


@router.post("/api/auth/logout")
def logout(body: RefreshIn):
    svc.logout(body.refresh_token)
    return {"ok": True}


@router.post("/api/auth/logout-all")
def logout_all(user=Depends(current_user)):
    svc.logout_all(user["id"])
    return {"ok": True}


@router.post("/api/auth/email/send-code")
def send_login_code(body: EmailCodeSendIn, request: Request):
    """邮箱验证码登录 / 注册：发码。无论邮箱是否注册，成功时都返回同样的结果。"""
    try:
        return svc.send_code(body.email, "login", ip=_ip(request))
    except svc.AuthError as e:
        _raise(e)


@router.post("/api/auth/email/login")
def login_with_code(body: EmailCodeLoginIn):
    try:
        return svc.login_with_code(body.email, body.code)
    except svc.AuthError as e:
        _raise(e)


@router.post("/api/me/email/send-verification")
def send_verification(request: Request, user=Depends(current_user)):
    if not user.get("email"):
        raise HTTPException(400, {"message": "当前账号没有绑定邮箱", "code": "no_email"})
    if user.get("email_verified"):
        return {"ok": True, "already_verified": True, "expires_in": 0, "retry_after": 0}
    try:
        return svc.send_code(user["email"], "verify", ip=_ip(request))
    except svc.AuthError as e:
        _raise(e)


@router.post("/api/me/email/verify")
def verify_email(body: EmailVerifyIn, user=Depends(current_user)):
    try:
        return svc.verify_email(user, body.code)
    except svc.AuthError as e:
        _raise(e)


@router.get("/api/me")
def me(user=Depends(current_user)):
    return user


@router.patch("/api/me")
def patch_me(body: NicknameIn, user=Depends(current_user)):
    """修改当前用户昵称。用户名不可改；空白 / 超长返回 422。"""
    return update_nickname(user["id"], body.nickname)
