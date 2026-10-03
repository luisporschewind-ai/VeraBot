#!/usr/bin/env python3
"""HTTP 缓存头（CACHE-01..08）：所有 /api/* 响应带 `Cache-Control: no-store`，客户端 / 代理不得存下
某个账号的数据。临时 SQLite + console 发信，不消耗 Token。

运行（在 backend/ 下）：uv run python scripts/test/cache_headers_test.py
"""
import io, os, sys, tempfile
from pathlib import Path

TMP = tempfile.mkdtemp(prefix="vb_cache_")
os.environ["VERABOT_DB"] = str(Path(TMP) / "t.db")
os.environ["VERABOT_DATA_DIR"] = TMP
os.environ["VERABOT_MAIL_BACKEND"] = "console"
os.environ.setdefault("DEEPSEEK_API_KEY", "test-not-used")
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from fastapi import FastAPI  # noqa: E402
from fastapi.responses import StreamingResponse  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from PIL import Image  # noqa: E402

from verabot import db  # noqa: E402
from verabot.core.http_cache import NoStoreAPIMiddleware, with_no_store  # noqa: E402
from verabot.main import app  # noqa: E402

db.init_db()
cli = TestClient(app)
PASSED = []


def check(name):
    def deco(fn):
        fn()
        PASSED.append(name)
        print(f"PASS {name} {fn.__doc__ or ''}".rstrip())
        return fn
    return deco


def no_store(r, expect="no-store"):
    cc = r.headers.get("cache-control")
    assert cc == expect, (r.request.method, r.request.url.path, r.status_code, cc)
    assert r.headers.get("pragma") == "no-cache", r.headers.get("pragma")
    assert len(r.headers.get_list("cache-control")) == 1, r.headers.get_list("cache-control")


def jpeg():
    buf = io.BytesIO()
    Image.new("RGB", (64, 64), (200, 30, 30)).save(buf, format="JPEG")
    return buf.getvalue()


auth = cli.post("/api/auth/register", json={"email": "cache@example.com", "password": "pass12345"})
assert auth.status_code == 200, auth.text
TOK = auth.json()["token"]
H = {"Authorization": f"Bearer {TOK}"}


@check("CACHE-01")
def auth_responses():
    """登录 / 注册 / 刷新（响应里有令牌）都是 no-store"""
    no_store(auth)
    login = cli.post("/api/auth/login", json={"identifier": "cache@example.com", "password": "pass12345"})
    assert login.status_code == 200
    no_store(login)
    ref = cli.post("/api/auth/refresh", json={"refresh_token": login.json()["refresh_token"]})
    assert ref.status_code == 200
    no_store(ref)


@check("CACHE-02")
def json_gets():
    """账号数据 GET：/api/me、bots、memories、mcp、quota、reminders、health"""
    bot = cli.post("/api/bots", headers=H, json={"name": "缓存测试"})
    assert bot.status_code == 201, bot.text
    no_store(bot)
    bid = bot.json()["id"]
    for path in ("/api/me", "/api/bots", f"/api/bots/{bid}", f"/api/bots/{bid}/messages", "/api/memories",
                 "/api/mcp/catalog", "/api/quota", "/api/reminders", "/api/tools", "/api/health"):
        r = cli.get(path, headers=H)
        assert r.status_code == 200, (path, r.status_code)
        no_store(r)


@check("CACHE-03")
def errors():
    """错误响应（401 / 404 / 422）也是 no-store"""
    no_store(cli.get("/api/bots"))                                   # 401 未登录
    no_store(cli.get("/api/bots/999999", headers=H))                 # 404
    no_store(cli.post("/api/auth/login", json={}))                   # 422
    no_store(cli.get("/api/does-not-exist", headers=H))              # 404 无路由


@check("CACHE-04")
def avatars():
    """头像：private, no-store（不再 max-age=86400），用户 / Bot 两种"""
    up = cli.post("/api/me/avatar", headers=H, files={"file": ("a.jpg", jpeg(), "image/jpeg")})
    assert up.status_code == 200, up.text
    no_store(up)
    got = cli.get("/api/me/avatar", headers=H)
    assert got.status_code == 200 and got.headers["content-type"] == "image/jpeg"
    no_store(got, "private, no-store")
    bid = cli.get("/api/bots", headers=H).json()["bots"][0]["id"]
    assert cli.post(f"/api/bots/{bid}/avatar", headers=H, files={"file": ("a.jpg", jpeg(), "image/jpeg")}).status_code in (200, 201)
    no_store(cli.get(f"/api/bots/{bid}/avatar", headers=H), "private, no-store")


@check("CACHE-05")
def cors_preflight():
    """CORS 预检（OPTIONS）也带 no-store，CORS 头不丢"""
    r = cli.options("/api/bots", headers={"Origin": "http://x.test", "Access-Control-Request-Method": "GET"})
    assert r.status_code == 200 and r.headers.get("access-control-allow-origin")
    no_store(r)


@check("CACHE-06")
def non_api_untouched():
    """非 /api/ 路径（首页、/docs）不加 no-store"""
    for path in ("/", "/docs", "/openapi.json"):
        r = cli.get(path)
        assert r.status_code == 200, path
        assert "no-store" not in (r.headers.get("cache-control") or ""), (path, r.headers.get("cache-control"))


@check("CACHE-07")
def streaming_passthrough():
    """SSE / 流式：no-cache 被替换为 no-store，其他头保留，响应体按块原样到达"""
    mini = FastAPI()

    @mini.get("/api/stream")
    def stream():
        def gen():
            for i in range(3):
                yield f"event: delta\ndata: {i}\n\n"
        return StreamingResponse(gen(), media_type="text/event-stream",
                                 headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})

    mini.add_middleware(NoStoreAPIMiddleware)
    with TestClient(mini).stream("GET", "/api/stream") as r:
        body = "".join(r.iter_text())
    assert r.headers["cache-control"] == "no-store" and r.headers["x-accel-buffering"] == "no"
    assert r.headers["content-type"].startswith("text/event-stream")
    assert body.count("event: delta") == 3, body
    # 真聊天接口：不存在的 Bot 先 404（同样 no-store）
    no_store(cli.post("/api/bots/999999/chat", headers=H, json={"message": "hi"}))


@check("CACHE-08")
def header_rules():
    """头处理规则：已含 no-store 的保留、其他替换、大小写不敏感、Pragma 不重复"""
    def cc(hs):
        return [v for k, v in with_no_store(hs) if k == b"cache-control"]
    assert cc([]) == [b"no-store"]
    assert cc([(b"Cache-Control", b"public, max-age=600")]) == [b"no-store"]
    assert cc([(b"cache-control", b"private, no-store")]) == [b"private, no-store"]
    assert cc([(b"CACHE-CONTROL", b"No-Store")]) == [b"No-Store"]
    out = with_no_store([(b"pragma", b"x"), (b"content-type", b"application/json")])
    assert [v for k, v in out if k == b"pragma"] == [b"no-cache"]
    assert (b"content-type", b"application/json") in out


print(f"CACHE tests passed: {len(PASSED)}/8 ({', '.join(PASSED)})")
assert len(PASSED) == 8
