#!/usr/bin/env python3
"""账号 v9（AUTH-01..18）：迁移、邮箱 / 手机号 / 用户名登录、锁定、刷新令牌轮换与复用检测、退出、
验证码登录与限流、邮箱验证、/api/me 字段、iOS 契约、未验证邮箱认领与已验证账号回归。只用临时 SQLite + console 邮件后端。"""
import os, re, sqlite3, sys, tempfile
from pathlib import Path

TMP = tempfile.mkdtemp(prefix="vb_auth_")
DB = str(Path(TMP) / "t.db")
os.environ["VERABOT_DB"] = DB
os.environ["VERABOT_DATA_DIR"] = TMP
os.environ["VERABOT_MAIL_BACKEND"] = "console"
os.environ.setdefault("DEEPSEEK_API_KEY", "test-not-used")
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
ROOT = Path(__file__).resolve().parents[3]

from verabot.core.security import hash_password  # noqa: E402

PASSED = []
def check(name):
    def deco(fn):
        ratelimit.reset()
        fn()
        PASSED.append(name)
        print(f"PASS {name}")
        return fn
    return deco

# AUTH-01: 旧库（v5 形态 + 用户名账号）迁移到 v9，老账号保留且能登录
c = sqlite3.connect(DB)
c.executescript("""
CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT UNIQUE NOT NULL, password_hash TEXT NOT NULL,
 created_at TEXT NOT NULL, token_budget INTEGER, nickname TEXT, avatar_updated_at TEXT, memory_enabled INTEGER DEFAULT 1);
CREATE TABLE schema_meta (key TEXT PRIMARY KEY,value TEXT NOT NULL);
INSERT INTO schema_meta VALUES ('version','5');
""")
c.execute("INSERT INTO users VALUES (1,'demo',?,'2026-01-01',NULL,'Boss',NULL,1)", (hash_password("verabot2026"),))
c.commit(); c.close()

from verabot import db  # noqa: E402
from verabot.core import ratelimit  # noqa: E402
from verabot.services import mailer  # noqa: E402
db.init_db(); db.init_db()
c = sqlite3.connect(DB)
cols = {r[1] for r in c.execute("PRAGMA table_info(users)")}
tables = {r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type IN ('table','index')")}
version = c.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()[0]
legacy = c.execute("SELECT username, nickname, email, phone, token_version FROM users WHERE id=1").fetchone()
c.close()
assert version == str(db.SCHEMA_VERSION) == "16", version
assert {"email", "email_verified_at", "phone", "token_version", "failed_logins", "locked_until"} <= cols
assert {"auth_codes", "auth_refresh_tokens", "idx_users_email", "idx_users_phone"} <= tables
assert legacy == ("demo", "Boss", None, None, 0)
PASSED.append("AUTH-01"); print("PASS AUTH-01 migration v5→v12 keeps legacy user")

from fastapi.testclient import TestClient  # noqa: E402
from verabot.main import app  # noqa: E402
cli = TestClient(app)


def H(tok):
    return {"Authorization": f"Bearer {tok}"}


def last_code(email):
    for m in reversed(mailer.OUTBOX):
        if m["to"] == email:
            return m["code"]
    raise AssertionError(f"no mail to {email}")


def detail_code(r):
    d = r.json().get("detail")
    return d.get("code") if isinstance(d, dict) else d


@check("AUTH-02")
def legacy_username_login():
    for body in ({"username": "demo", "password": "verabot2026"}, {"identifier": "demo", "password": "verabot2026"}):
        r = cli.post("/api/auth/login", json=body)
        assert r.status_code == 200, r.text
        j = r.json()
        assert j["token"] and j["refresh_token"] and j["expires_in"] == 7 * 24 * 3600
        assert j["user"]["username"] == "demo" and j["user"]["email"] is None and j["user"]["display_name"] == "Boss"
    r = cli.post("/api/auth/login", json={"username": "demo", "password": "nope"})
    assert r.status_code == 401 and r.json()["detail"] == "用户名或密码错误"
    # 旧的用户名注册仍然可用（6 位最少）
    r = cli.post("/api/auth/register", json={"username": "legacy2", "password": "pw1234"})
    assert r.status_code == 200 and r.json()["refresh_token"]


@check("AUTH-03")
def email_register_and_login():
    r = cli.post("/api/auth/register", json={"email": " Luis@Example.COM ", "password": "pass12345"})
    assert r.status_code == 200, r.text
    u = r.json()["user"]
    assert u["email"] == "luis@example.com" and u["email_verified"] is False and u["phone"] is None
    assert u["username"].startswith("u_") and u["display_name"] == "luis"
    assert last_code("luis@example.com")             # 注册时自动发验证邮件
    r = cli.post("/api/auth/login", json={"identifier": "LUIS@example.com", "password": "pass12345"})
    assert r.status_code == 200 and r.json()["user"]["id"] == u["id"]
    r = cli.post("/api/auth/login", json={"identifier": "luis@example.com", "password": "wrongpass"})
    assert r.status_code == 401 and r.json()["detail"] == "账号或密码错误"
    r = cli.post("/api/auth/login", json={"identifier": "nobody@example.com", "password": "wrongpass"})
    assert r.status_code == 401 and r.json()["detail"] == "账号或密码错误"   # 不区分账号是否存在


@check("AUTH-04")
def register_validation():
    r = cli.post("/api/auth/register", json={"email": "luis@example.com", "password": "pass12345"})
    assert r.status_code == 409 and detail_code(r) == "email_taken"
    r = cli.post("/api/auth/register", json={"email": "bad-email", "password": "pass12345"})
    assert r.status_code == 422 and detail_code(r) == "invalid_email"
    r = cli.post("/api/auth/register", json={"email": "short@example.com", "password": "1234567"})
    assert r.status_code == 422 and detail_code(r) == "weak_password"
    r = cli.post("/api/auth/register", json={"phone": "12345", "password": "pass12345"})
    assert r.status_code == 422 and detail_code(r) == "invalid_phone"


@check("AUTH-05")
def phone_register_and_login():
    r = cli.post("/api/auth/register", json={"phone": "138 0013 8000", "password": "phone1234"})
    assert r.status_code == 200, r.text
    u = r.json()["user"]
    assert u["phone"] == "+8613800138000" and u["email"] is None and u["display_name"] == "用户8000"
    for ident in ("13800138000", "+86 138-0013-8000", "008613800138000"):
        r = cli.post("/api/auth/login", json={"identifier": ident, "password": "phone1234"})
        assert r.status_code == 200 and r.json()["user"]["id"] == u["id"], ident
    r = cli.post("/api/auth/register", json={"phone": "+8613800138000", "password": "phone1234"})
    assert r.status_code == 409 and detail_code(r) == "phone_taken"


@check("AUTH-06")
def lockout():
    cli.post("/api/auth/register", json={"email": "lock@example.com", "password": "lockpass1"})
    for _ in range(5):
        assert cli.post("/api/auth/login", json={"identifier": "lock@example.com", "password": "x" * 8}).status_code == 401
    r = cli.post("/api/auth/login", json={"identifier": "lock@example.com", "password": "lockpass1"})
    assert r.status_code == 429 and detail_code(r) == "account_locked"
    with db.tx() as c:
        c.execute("UPDATE users SET locked_until='2000-01-01T00:00:00+00:00' WHERE email='lock@example.com'")
    r = cli.post("/api/auth/login", json={"identifier": "lock@example.com", "password": "lockpass1"})
    assert r.status_code == 200
    with db.tx() as c:
        assert tuple(c.execute("SELECT failed_logins, locked_until FROM users WHERE email='lock@example.com'").fetchone()) == (0, None)


@check("AUTH-07")
def refresh_rotation_and_reuse():
    s = cli.post("/api/auth/login", json={"identifier": "luis@example.com", "password": "pass12345"}).json()
    r = cli.post("/api/auth/refresh", json={"refresh_token": s["refresh_token"]})
    assert r.status_code == 200
    s2 = r.json()
    assert s2["refresh_token"] != s["refresh_token"] and cli.get("/api/me", headers=H(s2["token"])).status_code == 200
    # 旧刷新令牌再次出现 → 复用：拒绝，并作废该用户所有刷新令牌（包括刚发的 s2）
    r = cli.post("/api/auth/refresh", json={"refresh_token": s["refresh_token"]})
    assert r.status_code == 401
    assert cli.post("/api/auth/refresh", json={"refresh_token": s2["refresh_token"]}).status_code == 401
    assert cli.post("/api/auth/refresh", json={"refresh_token": "garbage"}).status_code == 401
    # 过期
    s3 = cli.post("/api/auth/login", json={"identifier": "luis@example.com", "password": "pass12345"}).json()
    with db.tx() as c:
        c.execute("UPDATE auth_refresh_tokens SET expires_at='2000-01-01T00:00:00+00:00' WHERE revoked_at IS NULL")
    assert cli.post("/api/auth/refresh", json={"refresh_token": s3["refresh_token"]}).status_code == 401


@check("AUTH-08")
def logout_and_logout_all():
    a = cli.post("/api/auth/login", json={"identifier": "luis@example.com", "password": "pass12345"}).json()
    b = cli.post("/api/auth/login", json={"identifier": "luis@example.com", "password": "pass12345"}).json()
    assert cli.post("/api/auth/logout", json={"refresh_token": a["refresh_token"]}).json() == {"ok": True}
    assert cli.post("/api/auth/refresh", json={"refresh_token": a["refresh_token"]}).status_code == 401
    assert cli.get("/api/me", headers=H(b["token"])).status_code == 200
    assert cli.post("/api/auth/logout-all", headers=H(b["token"])).json() == {"ok": True}
    r = cli.get("/api/me", headers=H(b["token"]))                     # token_version 变了，旧访问令牌失效
    assert r.status_code == 401 and "登录已失效" in r.json()["detail"]
    assert cli.post("/api/auth/refresh", json={"refresh_token": b["refresh_token"]}).status_code == 401
    c2 = cli.post("/api/auth/login", json={"identifier": "luis@example.com", "password": "pass12345"}).json()
    assert cli.get("/api/me", headers=H(c2["token"])).status_code == 200


@check("AUTH-09")
def code_login_creates_account():
    r = cli.post("/api/auth/email/send-code", json={"email": "New@Example.com"})
    assert r.status_code == 200 and r.json() == {"ok": True, "expires_in": 600, "retry_after": 60}
    code = last_code("new@example.com")
    bad = "000000" if code != "000000" else "111111"
    r = cli.post("/api/auth/email/login", json={"email": "new@example.com", "code": bad})
    assert r.status_code == 400 and detail_code(r) == "code_invalid"
    r = cli.post("/api/auth/email/login", json={"email": "new@example.com", "code": code})
    assert r.status_code == 200, r.text
    u = r.json()["user"]
    assert u["email"] == "new@example.com" and u["email_verified"] is True
    r = cli.post("/api/auth/email/login", json={"email": "new@example.com", "code": code})   # 一次性
    assert r.status_code == 400 and detail_code(r) == "code_expired"
    # 已验证的邮箱账号用验证码登录 → 同一个账号（未验证账号的认领会清密码，见 AUTH-17）
    with db.tx() as c:
        c.execute("UPDATE users SET email_verified_at=COALESCE(email_verified_at, ?) WHERE email='luis@example.com'",
                  (db.now_iso(),))
    ratelimit.reset()
    cli.post("/api/auth/email/send-code", json={"email": "luis@example.com"})
    r = cli.post("/api/auth/email/login", json={"email": "luis@example.com", "code": last_code("luis@example.com")})
    assert r.status_code == 200 and r.json()["user"]["display_name"] == "luis"
    assert cli.post("/api/auth/login", json={"identifier": "luis@example.com", "password": "pass12345"}).status_code == 200


@check("AUTH-10")
def code_limits():
    assert cli.post("/api/auth/email/send-code", json={"email": "cool@example.com"}).status_code == 200
    first = last_code("cool@example.com")
    r = cli.post("/api/auth/email/send-code", json={"email": "cool@example.com"})
    assert r.status_code == 429 and detail_code(r) == "code_cooldown"
    for i in range(5):
        r = cli.post("/api/auth/email/login", json={"email": "cool@example.com", "code": "%06d" % ((int(first) + 1 + i) % 1000000)})
        assert r.status_code == 400
    r = cli.post("/api/auth/email/login", json={"email": "cool@example.com", "code": first})
    assert r.status_code == 400 and detail_code(r) in ("code_exhausted", "code_expired")   # 5 次错后作废
    ratelimit.reset()
    cli.post("/api/auth/email/send-code", json={"email": "cool@example.com"})
    with db.tx() as c:
        c.execute("UPDATE auth_codes SET expires_at='2000-01-01T00:00:00+00:00' WHERE email='cool@example.com'")
    r = cli.post("/api/auth/email/login", json={"email": "cool@example.com", "code": last_code("cool@example.com")})
    assert r.status_code == 400 and detail_code(r) == "code_expired"
    # 新码让旧码作废
    ratelimit.reset()
    cli.post("/api/auth/email/send-code", json={"email": "rot@example.com"}); old = last_code("rot@example.com")
    ratelimit.reset()
    cli.post("/api/auth/email/send-code", json={"email": "rot@example.com"}); new = last_code("rot@example.com")
    if old != new:
        assert cli.post("/api/auth/email/login", json={"email": "rot@example.com", "code": old}).status_code == 400
    assert cli.post("/api/auth/email/login", json={"email": "rot@example.com", "code": new}).status_code == 200
    r = cli.post("/api/auth/email/send-code", json={"email": "nope"})
    assert r.status_code == 422


@check("AUTH-11")
def verify_email():
    s = cli.post("/api/auth/login", json={"identifier": "luis@example.com", "password": "pass12345"}).json()
    with db.tx() as c:
        c.execute("UPDATE users SET email_verified_at=NULL WHERE email='luis@example.com'")
    assert cli.get("/api/me", headers=H(s["token"])).json()["email_verified"] is False
    r = cli.post("/api/me/email/send-verification", headers=H(s["token"]))
    assert r.status_code == 200 and r.json()["ok"]
    r = cli.post("/api/me/email/verify", json={"code": "999999" if last_code("luis@example.com") != "999999" else "888888"},
                 headers=H(s["token"]))
    assert r.status_code == 400
    r = cli.post("/api/me/email/verify", json={"code": last_code("luis@example.com")}, headers=H(s["token"]))
    assert r.status_code == 200 and r.json()["email_verified"] is True
    ratelimit.reset()
    r = cli.post("/api/me/email/send-verification", headers=H(s["token"]))
    assert r.json().get("already_verified") is True
    # 没有邮箱的账号
    d = cli.post("/api/auth/login", json={"identifier": "demo", "password": "verabot2026"}).json()
    r = cli.post("/api/me/email/send-verification", headers=H(d["token"]))
    assert r.status_code == 400


@check("AUTH-12")
def me_fields_and_tokens():
    s = cli.post("/api/auth/login", json={"identifier": "13800138000", "password": "phone1234"}).json()
    me = cli.get("/api/me", headers=H(s["token"])).json()
    assert {"id", "username", "nickname", "display_name", "has_avatar", "avatar_updated_at",
            "email", "email_verified", "phone"} <= set(me)
    assert "password_hash" not in me and "token_version" not in me and "failed_logins" not in me
    import jwt
    from verabot.core.config import JWT_SECRET
    claims = jwt.decode(s["token"], JWT_SECRET, algorithms=["HS256"])
    assert claims["typ"] == "access" and claims["tv"] == 0
    assert 7 * 86400 - 120 <= claims["exp"] - claims["iat"] <= 7 * 86400 + 120 if "iat" in claims else True
    assert s["refresh_expires_in"] == 60 * 86400
    # 不带 tv 的旧令牌（v8 签发）仍然有效，等价 tv=0
    old = jwt.encode({k: v for k, v in claims.items() if k not in ("tv", "typ")}, JWT_SECRET, algorithm="HS256")
    assert cli.get("/api/me", headers=H(old)).status_code == 200
    # 刷新令牌不能当访问令牌
    assert cli.get("/api/me", headers=H(s["refresh_token"])).status_code == 401
    # 改昵称后 display_name 用昵称
    assert cli.patch("/api/me", json={"nickname": "小手机"}, headers=H(s["token"])).json()["display_name"] == "小手机"


@check("AUTH-13")
def ip_limit():
    os.environ["VERABOT_AUTH_IP_LIMIT"] = "3"
    try:
        codes = [cli.post("/api/auth/login", json={"identifier": "nobody@example.com", "password": "badpass1"}).status_code
                 for _ in range(5)]
        assert codes[:3] == [401, 401, 401] and codes[3] == 429, codes
    finally:
        os.environ.pop("VERABOT_AUTH_IP_LIMIT", None)


@check("AUTH-14")
def mail_backends():
    n = len(mailer.OUTBOX)
    mailer.send("x@example.com", "s", "body 123456", code="123456")
    assert len(mailer.OUTBOX) == n + 1 and mailer.OUTBOX[-1]["code"] == "123456"
    os.environ["VERABOT_MAIL_BACKEND"] = "smtp"
    os.environ.pop("VERABOT_SMTP_USER", None)
    try:
        try:
            mailer.send("x@example.com", "s", "b", code="1")
            raise AssertionError("smtp without credentials should fail")
        except mailer.MailError:
            pass
        # 发码时邮件失败 → 503 mail_failed
        r = cli.post("/api/auth/email/send-code", json={"email": "smtpfail@example.com"})
        assert r.status_code == 503 and detail_code(r) == "mail_failed"
    finally:
        os.environ["VERABOT_MAIL_BACKEND"] = "console"


@check("AUTH-15")
def ios_contract():
    """iOS Codable 的 JSON 键 ⊆ 后端实际返回 / 接受的键（字段映射清单见 AUTH_REFACTOR.md §7）。"""
    core = ROOT / "frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore"
    auth_src = (core / "Auth.swift").read_text()
    models_src = (core / "Models.swift").read_text()

    def keys(src, name):
        m = re.search(rf"struct {name}\b.*?enum CodingKeys: String, CodingKey \{{(.*?)\n    \}}", src, re.S)
        assert m, name
        out = set()
        for line in m.group(1).splitlines():
            line = line.strip()
            if not line.startswith("case "):
                continue
            rest = line[5:]
            if "=" in rest:
                out.add(rest.split("=", 1)[1].strip().strip('"'))
            else:
                out.update(p.strip() for p in rest.split(",") if p.strip())
        return out

    ratelimit.reset()
    reg = cli.post("/api/auth/register", json={"email": "contract@example.com", "password": "pass12345"}).json()
    assert keys(auth_src, "AuthResponse") <= set(reg), keys(auth_src, "AuthResponse") - set(reg)
    assert keys(models_src, "User") <= set(reg["user"]), keys(models_src, "User") - set(reg["user"])
    assert keys(models_src, "User") >= {"email", "email_verified", "phone"}
    sent = cli.post("/api/auth/email/send-code", json={"email": "contract2@example.com"}).json()
    assert keys(auth_src, "CodeSentResponse") <= set(sent)
    from verabot.api import schemas
    def fields(model):
        return set(model.model_fields)
    assert keys(auth_src, "LoginRequest") <= fields(schemas.LoginIn)
    assert keys(auth_src, "RegisterRequest") <= fields(schemas.RegisterIn)
    assert keys(auth_src, "EmailCodeRequest") <= fields(schemas.EmailCodeSendIn)
    assert keys(auth_src, "EmailCodeLoginRequest") <= fields(schemas.EmailCodeLoginIn)
    assert keys(auth_src, "EmailVerifyRequest") <= fields(schemas.EmailVerifyIn)
    assert keys(auth_src, "RefreshRequest") <= fields(schemas.RefreshIn)
    # iOS 路径与后端路由一致
    client = (ROOT / "frontend/ios/Packages/VeraBotKit/Sources/VeraBotNetworking/APIClient.swift").read_text()
    routes = set(app.openapi()["paths"])
    for p in ("/api/auth/login", "/api/auth/register", "/api/auth/refresh", "/api/auth/logout",
              "/api/auth/email/send-code", "/api/auth/email/login", "/api/me/email/send-verification", "/api/me/email/verify"):
        assert f'"{p}"' in client and p in routes, p
    session = (ROOT / "frontend/ios/Packages/VeraBotKit/Sources/VeraBotNetworking/AuthSession.swift").read_text()
    assert '"/api/auth/refresh"' in session


@check("AUTH-16")
def classify_and_normalize():
    from verabot.services import auth as svc
    assert svc.classify_identifier("Demo") == ("username", "Demo") or svc.classify_identifier("Demo")[0] == "username"
    assert svc.classify_identifier("A@B.co")[0] == "email"
    assert svc.classify_identifier("+1 415 555 0123") == ("phone", "+14155550123")
    assert svc.normalize_phone("0086 138 0013 8000") == "+8613800138000"


@check("AUTH-17")
def email_squat_claim():
    """未验证邮箱被抢注后，真正持有者用验证码登录会认领同一账号并踢掉抢注者。"""
    email = "squat@example.com"
    reg = cli.post("/api/auth/register", json={"email": email, "password": "attacker1"})
    assert reg.status_code == 200, reg.text
    attacker = reg.json()
    uid = attacker["user"]["id"]
    assert attacker["user"]["email_verified"] is False
    second = cli.post("/api/auth/login", json={"identifier": email, "password": "attacker1"})
    assert second.status_code == 200, second.text
    second = second.json()
    assert cli.get("/api/me", headers=H(attacker["token"])).status_code == 200
    assert cli.get("/api/me", headers=H(second["token"])).status_code == 200
    dev = cli.post("/api/devices", json={"device_id": "squat-phone", "platform": "ios"}, headers=H(attacker["token"]))
    assert dev.status_code == 200, dev.text
    with db.tx() as c:
        tv_before = c.execute("SELECT token_version FROM users WHERE id=?", (uid,)).fetchone()[0]
    ratelimit.reset()
    sent = cli.post("/api/auth/email/send-code", json={"email": email})
    assert sent.status_code == 200, sent.text
    claimed = cli.post("/api/auth/email/login", json={"email": email, "code": last_code(email)})
    assert claimed.status_code == 200, claimed.text
    owner = claimed.json()
    assert owner["user"]["id"] == uid and owner["user"]["email_verified"] is True
    assert owner["token"] and owner["refresh_token"]
    # 先看认领事务的结果。之后再拿抢注者的旧刷新令牌来换新的，会命中既有的「已吊销令牌复用」逻辑，
    # 把主人刚拿到的刷新令牌也作废；那一步不能用来判断认领本身留了几枚令牌。
    with db.tx() as c:
        pw, tv, verified = c.execute(
            "SELECT password_hash, token_version, email_verified_at FROM users WHERE id=?", (uid,)).fetchone()
        audit = c.execute(
            "SELECT COUNT(*) FROM audit_log WHERE user_id=? AND kind='account_claimed_by_email_code'",
            (uid,)).fetchone()[0]
        live = c.execute(
            "SELECT COUNT(*) FROM auth_refresh_tokens WHERE user_id=? AND revoked_at IS NULL", (uid,)).fetchone()[0]
        disabled = c.execute(
            "SELECT disabled_at FROM push_devices WHERE user_id=? AND device_id='squat-phone'", (uid,)).fetchone()[0]
    assert pw == "" and verified and tv == tv_before + 1 and audit == 1 and live == 1
    assert disabled
    bad = cli.post("/api/auth/login", json={"identifier": email, "password": "attacker1"})
    assert bad.status_code == 401 and bad.json()["detail"] == "账号或密码错误"
    for tok in (attacker["token"], second["token"]):
        r = cli.get("/api/me", headers=H(tok))
        assert r.status_code == 401 and "登录已失效" in r.json()["detail"]
    for refresh in (attacker["refresh_token"], second["refresh_token"]):
        assert cli.post("/api/auth/refresh", json={"refresh_token": refresh}).status_code == 401
    assert cli.get("/api/me", headers=H(owner["token"])).status_code == 200


@check("AUTH-18")
def code_login_verified_unchanged():
    """已验证邮箱的验证码登录不改密码、不增加 token_version、不吊销已有会话。"""
    email = "verified-keep@example.com"
    reg = cli.post("/api/auth/register", json={"email": email, "password": "ownerpass1"})
    assert reg.status_code == 200, reg.text
    uid = reg.json()["user"]["id"]
    with db.tx() as c:
        c.execute("UPDATE users SET email_verified_at=? WHERE id=?", (db.now_iso(), uid))
        before = c.execute("SELECT password_hash, token_version FROM users WHERE id=?", (uid,)).fetchone()
    sess = cli.post("/api/auth/login", json={"identifier": email, "password": "ownerpass1"})
    assert sess.status_code == 200, sess.text
    sess = sess.json()
    dev = cli.post("/api/devices", json={"device_id": "keep-phone", "platform": "ios"}, headers=H(sess["token"]))
    assert dev.status_code == 200, dev.text
    ratelimit.reset()
    assert cli.post("/api/auth/email/send-code", json={"email": email}).status_code == 200
    r = cli.post("/api/auth/email/login", json={"email": email, "code": last_code(email)})
    assert r.status_code == 200, r.text
    owner = r.json()
    assert owner["user"]["id"] == uid and owner["user"]["email_verified"] is True
    assert cli.post("/api/auth/login", json={"identifier": email, "password": "ownerpass1"}).status_code == 200
    assert cli.get("/api/me", headers=H(sess["token"])).status_code == 200
    assert cli.post("/api/auth/refresh", json={"refresh_token": sess["refresh_token"]}).status_code == 200
    assert cli.get("/api/me", headers=H(owner["token"])).status_code == 200
    with db.tx() as c:
        after = c.execute("SELECT password_hash, token_version FROM users WHERE id=?", (uid,)).fetchone()
        claimed = c.execute(
            "SELECT COUNT(*) FROM audit_log WHERE user_id=? AND kind='account_claimed_by_email_code'",
            (uid,)).fetchone()[0]
        disabled = c.execute(
            "SELECT disabled_at FROM push_devices WHERE user_id=? AND device_id='keep-phone'", (uid,)).fetchone()[0]
    assert after == before and claimed == 0 and disabled is None


print(f"AUTH tests passed: {len(PASSED)}/18 ({', '.join(PASSED)})")
assert len(PASSED) == 18
