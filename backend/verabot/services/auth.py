"""账号（Auth，schema v9）：邮箱 / 手机号 / 用户名登录、邮箱验证码、刷新令牌。设计见 docs/design/AUTH_REFACTOR.md。

HTTP 无关：出错抛 AuthError(status, message, code)，路由层转成 HTTPException。
"""
from __future__ import annotations

import json
import re
import secrets
from datetime import datetime, timedelta, timezone

from .. import db
from ..core import ratelimit
from ..core.config import (AUTH_CODE_COOLDOWN_SECONDS, AUTH_CODE_DAILY_LIMIT, AUTH_CODE_MAX_ATTEMPTS,
                           AUTH_CODE_TTL_SECONDS, AUTH_LOCK_MINUTES, AUTH_LOCK_THRESHOLD, REFRESH_TTL_DAYS,
                           TOKEN_TTL_HOURS)
from ..core.security import hash_password, hash_secret, issue_token, new_secret, verify_password
from . import mailer
from .users import public_user

EMAIL_RE = re.compile(r"^[^@\s]{1,64}@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9-]{1,63})+$")
PHONE_RE = re.compile(r"^\+[1-9]\d{7,14}$")
PASSWORD_MIN = 8               # 邮箱 / 手机号新账号；老的用户名注册仍是 6
GENERIC_LOGIN_ERROR = "账号或密码错误"


class AuthError(Exception):
    def __init__(self, status: int, message: str, code: str):
        super().__init__(message)
        self.status, self.message, self.code = status, message, code


# ---------- 规范化 ----------

def normalize_email(raw: str) -> str:
    v = (raw or "").strip().lower()
    if len(v) > 254 or not EMAIL_RE.match(v):
        raise AuthError(422, "邮箱格式不正确", "invalid_email")
    return v


def normalize_phone(raw: str) -> str:
    """接受 +86 13800138000 / 13800138000 / +1 4155550123 等，统一成 E.164。"""
    v = re.sub(r"[\s\-()]", "", raw or "")
    if re.fullmatch(r"1[3-9]\d{9}", v):          # 中国大陆 11 位手机号，默认 +86
        v = "+86" + v
    elif v.startswith("0086"):
        v = "+" + v[2:]
    if not PHONE_RE.match(v):
        raise AuthError(422, "手机号格式不正确", "invalid_phone")
    return v


def check_password(pw: str) -> str:
    if not isinstance(pw, str) or len(pw) < PASSWORD_MIN:
        raise AuthError(422, f"密码至少 {PASSWORD_MIN} 位", "weak_password")
    if len(pw) > 128:
        raise AuthError(422, "密码最多 128 位", "weak_password")
    return pw


def classify_identifier(raw: str) -> tuple[str, str]:
    """登录框里的「账号」：含 @ 是邮箱；以 + 或数字开头且像手机号是手机号；否则当用户名（demo 等老账号）。"""
    v = (raw or "").strip()
    if "@" in v:
        return "email", normalize_email(v)
    digits = re.sub(r"[\s\-()]", "", v)
    if digits.startswith("+") or (digits.isdigit() and len(digits) >= 8):
        return "phone", normalize_phone(v)
    return "username", v


# ---------- 会话（访问令牌 + 刷新令牌） ----------

def _audit(c, user_id: int, bot_id, kind: str, detail: dict) -> None:
    """审计写在同一个连接 / 事务里：db.audit() 另开连接，在未提交的写事务里调用会等锁。"""
    c.execute("INSERT INTO audit_log(user_id,bot_id,kind,detail,created_at) VALUES (?,?,?,?,?)",
              (user_id, bot_id, kind, json.dumps(detail, ensure_ascii=False), db.now_iso()))


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _iso(dt: datetime) -> str:
    return dt.isoformat(timespec="seconds")


def issue_session(c, u: dict) -> dict:
    """在同一事务里签发访问令牌和一个新的刷新令牌。"""
    refresh = new_secret()
    now = _now()
    c.execute("INSERT INTO auth_refresh_tokens(user_id, token_hash, expires_at, created_at) VALUES (?,?,?,?)",
              (u["id"], hash_secret(refresh), _iso(now + timedelta(days=REFRESH_TTL_DAYS)), _iso(now)))
    return {
        "token": issue_token(u["id"], u["username"], u.get("token_version") or 0),
        "refresh_token": refresh,
        "expires_in": TOKEN_TTL_HOURS * 3600,
        "refresh_expires_in": REFRESH_TTL_DAYS * 86400,
        "user": public_user(u),
    }


def _user_by(c, column: str, value: str) -> dict | None:
    assert column in ("id", "username", "email", "phone")
    return db.row(c.execute(f"SELECT * FROM users WHERE {column}=?", (value,)).fetchone())


def _new_username(c) -> str:
    """邮箱 / 手机号账号的内部用户名（兼容字段，界面不展示）。"""
    while True:
        name = "u_" + secrets.token_hex(5)
        if not c.execute("SELECT 1 FROM users WHERE username=?", (name,)).fetchone():
            return name


def _create_user(c, *, email: str | None = None, phone: str | None = None, password: str | None = None,
                 email_verified: bool = False) -> dict:
    created = db.now_iso()
    pw_hash = hash_password(password if password else new_secret())   # 验证码注册的账号没有可用密码
    uid = c.execute(
        "INSERT INTO users(username, password_hash, created_at, email, email_verified_at, phone) VALUES (?,?,?,?,?,?)",
        (_new_username(c), pw_hash, created, email, created if email_verified else None, phone),
    ).lastrowid
    return _user_by(c, "id", uid)


def register(*, email: str | None, phone: str | None, password: str) -> dict:
    if bool(email) == bool(phone):
        raise AuthError(422, "请填写邮箱或手机号其中一项", "invalid_request")
    check_password(password)
    with db.tx() as c:
        if email:
            email = normalize_email(email)
            if _user_by(c, "email", email):
                raise AuthError(409, "该邮箱已注册，请直接登录", "email_taken")
            u = _create_user(c, email=email, password=password)
        else:
            phone = normalize_phone(phone or "")
            if _user_by(c, "phone", phone):
                raise AuthError(409, "该手机号已注册，请直接登录", "phone_taken")
            u = _create_user(c, phone=phone, password=password)
        _audit(c, u["id"], None, "auth_register", {"method": "email" if email else "phone"})
        out = issue_session(c, u)
    if email:
        try:   # 注册后发一封验证邮件；发信失败不影响注册（设置页可重发）
            send_code(email, "verify", ip=None, quiet=True)
        except AuthError:
            pass
    return out


def register_username(username: str, password: str) -> dict:
    """老接口 {username, password}：保留给 demo / 测试脚本 / Web。"""
    with db.tx() as c:
        if _user_by(c, "username", username):
            raise AuthError(409, "用户名已存在", "username_taken")
        created = db.now_iso()
        uid = c.execute("INSERT INTO users(username,password_hash,created_at) VALUES (?,?,?)",
                        (username, hash_password(password), created)).lastrowid
        return issue_session(c, _user_by(c, "id", uid))


def login(identifier: str, password: str) -> dict:
    kind, value = classify_identifier(identifier)
    with db.tx() as c:
        u = _user_by(c, kind, value)
        if u and u.get("locked_until") and u["locked_until"] > _iso(_now()):
            raise AuthError(429, f"密码错误次数过多，请 {AUTH_LOCK_MINUTES} 分钟后再试", "account_locked")
        if not u or not verify_password(password, u["password_hash"]):
            if u:
                failures = int(u.get("failed_logins") or 0) + 1
                locked = _iso(_now() + timedelta(minutes=AUTH_LOCK_MINUTES)) if failures >= AUTH_LOCK_THRESHOLD else None
                c.execute("UPDATE users SET failed_logins=?, locked_until=? WHERE id=?",
                          (0 if locked else failures, locked, u["id"]))
                if locked:
                    _audit(c, u["id"], None, "auth_locked", {"method": kind})
                c.commit()   # 失败计数要落库：抛错会让 db.tx() 回滚
            raise AuthError(401, GENERIC_LOGIN_ERROR, "invalid_credentials")
        if u.get("failed_logins") or u.get("locked_until"):
            c.execute("UPDATE users SET failed_logins=0, locked_until=NULL WHERE id=?", (u["id"],))
        _audit(c, u["id"], None, "auth_login", {"method": kind})
        return issue_session(c, u)


def refresh(token: str) -> dict:
    """轮换刷新令牌：旧的作废、发新的一对。已作废的令牌再次出现 → 视为泄露，作废该用户全部刷新令牌。"""
    h = hash_secret(token or "")
    with db.tx() as c:
        r = db.row(c.execute("SELECT * FROM auth_refresh_tokens WHERE token_hash=?", (h,)).fetchone())
        if r is None:
            raise AuthError(401, "登录已失效，请重新登录", "invalid_refresh")
        now = _iso(_now())
        if r["revoked_at"]:
            c.execute("UPDATE auth_refresh_tokens SET revoked_at=? WHERE user_id=? AND revoked_at IS NULL",
                      (now, r["user_id"]))
            _audit(c, r["user_id"], None, "auth_refresh_reuse", {})
            c.commit()   # 先落库再抛错（db.tx() 出错会回滚）
            raise AuthError(401, "登录已失效，请重新登录", "refresh_reused")
        if r["expires_at"] <= now:
            raise AuthError(401, "登录已失效，请重新登录", "refresh_expired")
        u = _user_by(c, "id", r["user_id"])
        if u is None:
            raise AuthError(401, "用户不存在", "invalid_refresh")
        c.execute("UPDATE auth_refresh_tokens SET revoked_at=? WHERE id=?", (now, r["id"]))
        return issue_session(c, u)


def logout(token: str | None) -> None:
    if not token:
        return
    with db.tx() as c:
        c.execute("UPDATE auth_refresh_tokens SET revoked_at=? WHERE token_hash=? AND revoked_at IS NULL",
                  (_iso(_now()), hash_secret(token)))


def logout_all(user_id: int) -> None:
    with db.tx() as c:
        c.execute("UPDATE users SET token_version = token_version + 1 WHERE id=?", (user_id,))
        c.execute("UPDATE auth_refresh_tokens SET revoked_at=? WHERE user_id=? AND revoked_at IS NULL",
                  (_iso(_now()), user_id))
        _audit(c, user_id, None, "auth_logout_all", {})


# ---------- 邮箱验证码 ----------

PURPOSES = ("login", "verify")
_SUBJECT = {"login": "VeraBot 登录验证码", "verify": "VeraBot 邮箱验证码"}


def send_code(email: str, purpose: str, *, ip: str | None, quiet: bool = False) -> dict:
    """发验证码。无论邮箱是否注册都返回同样的结果（防枚举）。限流：同一邮箱 60 秒 1 次、每天 10 次；同一 IP 每小时 30 次。"""
    if purpose not in PURPOSES:
        raise AuthError(422, "purpose 只能是 login 或 verify", "invalid_request")
    email = normalize_email(email)
    if ip and not ratelimit.hit(f"code-ip:{ip}", 30, 3600):
        raise AuthError(429, "请求过于频繁，请稍后再试", "rate_limited")
    if not ratelimit.hit(f"code-cool:{email}", 1, AUTH_CODE_COOLDOWN_SECONDS):
        wait = ratelimit.retry_after(f"code-cool:{email}", AUTH_CODE_COOLDOWN_SECONDS)
        raise AuthError(429, f"验证码发送太频繁，请 {wait} 秒后再试", "code_cooldown")
    if not ratelimit.hit(f"code-day:{email}", AUTH_CODE_DAILY_LIMIT, 86400):
        raise AuthError(429, "今天的验证码次数已用完，请明天再试", "code_daily_limit")
    code = f"{secrets.randbelow(1_000_000):06d}"
    now = _now()
    with db.tx() as c:
        # 同一邮箱同一用途只保留最新的一条：旧码作废
        c.execute("UPDATE auth_codes SET consumed_at=? WHERE email=? AND purpose=? AND consumed_at IS NULL",
                  (_iso(now), email, purpose))
        c.execute("INSERT INTO auth_codes(email, purpose, code_hash, expires_at, created_at) VALUES (?,?,?,?,?)",
                  (email, purpose, hash_secret(f"{email}:{purpose}:{code}"),
                   _iso(now + timedelta(seconds=AUTH_CODE_TTL_SECONDS)), _iso(now)))
    minutes = max(1, AUTH_CODE_TTL_SECONDS // 60)
    body = f"你的 VeraBot 验证码是 {code}，{minutes} 分钟内有效。\n如果不是你本人操作，请忽略这封邮件。"
    try:
        mailer.send(email, _SUBJECT[purpose], body, code=code)
    except mailer.MailError:
        if not quiet:
            raise AuthError(503, "验证码邮件发送失败，请稍后再试", "mail_failed")
    return {"ok": True, "expires_in": AUTH_CODE_TTL_SECONDS, "retry_after": AUTH_CODE_COOLDOWN_SECONDS}


def _consume_code(c, email: str, purpose: str, code: str) -> None:
    r = db.row(c.execute(
        "SELECT * FROM auth_codes WHERE email=? AND purpose=? AND consumed_at IS NULL ORDER BY id DESC LIMIT 1",
        (email, purpose)).fetchone())
    now = _iso(_now())
    if r is None or r["expires_at"] <= now:
        raise AuthError(400, "验证码已过期，请重新获取", "code_expired")
    if r["attempts"] >= AUTH_CODE_MAX_ATTEMPTS:
        raise AuthError(400, "验证码错误次数过多，请重新获取", "code_exhausted")
    code = (code or "").strip()
    if not secrets.compare_digest(r["code_hash"], hash_secret(f"{email}:{purpose}:{code}")):
        attempts = r["attempts"] + 1
        c.execute("UPDATE auth_codes SET attempts=?, consumed_at=? WHERE id=?",
                  (attempts, now if attempts >= AUTH_CODE_MAX_ATTEMPTS else None, r["id"]))
        c.commit()   # 错误次数要落库：抛错会让 db.tx() 回滚
        raise AuthError(400, "验证码不正确", "code_invalid")
    c.execute("UPDATE auth_codes SET consumed_at=? WHERE id=?", (now, r["id"]))


def login_with_code(email: str, code: str) -> dict:
    """邮箱验证码登录。邮箱还没有账号时直接创建（邮箱视为已验证，没有密码）。"""
    email = normalize_email(email)
    with db.tx() as c:
        _consume_code(c, email, "login", code)
        u = _user_by(c, "email", email)
        created = u is None
        if created:
            u = _create_user(c, email=email, email_verified=True)
        elif not u.get("email_verified_at"):
            c.execute("UPDATE users SET email_verified_at=? WHERE id=?", (db.now_iso(), u["id"]))
            u = _user_by(c, "id", u["id"])
        _audit(c, u["id"], None, "auth_login", {"method": "email_code", "created": created})
        return issue_session(c, u)


def verify_email(user: dict, code: str) -> dict:
    """已登录用户验证自己的邮箱（注册时自动发过一封；设置页可重发）。"""
    email = user.get("email")
    if not email:
        raise AuthError(400, "当前账号没有绑定邮箱", "no_email")
    with db.tx() as c:
        _consume_code(c, email, "verify", code)
        c.execute("UPDATE users SET email_verified_at=? WHERE id=?", (db.now_iso(), user["id"]))
        _audit(c, user["id"], None, "auth_email_verified", {})
        return public_user(_user_by(c, "id", user["id"]))
