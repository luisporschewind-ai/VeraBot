#!/usr/bin/env python3
"""MCP M1：本地假服务器（JSON / SSE）、迁移 v6→v7、工具开关、前后端字段契约。

真实 Microsoft Learn / AWS 调用默认跳过。设置 VERABOT_MCP_LIVE_TESTS=1 才发外网请求。
"""
import json, os, sqlite3, sys, tempfile, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TMP = tempfile.mkdtemp(prefix="vb_mcp_")
DB = str(Path(TMP) / "t.db")
os.environ["VERABOT_DB"] = DB
os.environ["VERABOT_DATA_DIR"] = TMP
os.environ.setdefault("DEEPSEEK_API_KEY", "test-not-used")
os.environ["VERABOT_MCP_AWS_ENABLED"] = "0"
ORIG_LEARN = os.environ.get("VERABOT_MCP_LEARN_URL")
ORIG_AWS = os.environ.get("VERABOT_MCP_AWS_URL")
ORIG_PROTO = os.environ.get("VERABOT_MCP_PROTOCOL_VERSION")
sys.path.insert(0, str(ROOT))

IOS = ROOT.parent / "frontend/ios/Packages/VeraBotKit/Sources"
FAILS = []


def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else " " + detail))
    if not ok:
        FAILS.append(name)


# ---------- 迁移：已有 v6 库 ----------
con = sqlite3.connect(DB)
con.executescript("""
CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT UNIQUE NOT NULL, password_hash TEXT NOT NULL,
 created_at TEXT NOT NULL, token_budget INTEGER, nickname TEXT, avatar_updated_at TEXT, memory_enabled INTEGER DEFAULT 1);
CREATE TABLE bots (id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL, name TEXT NOT NULL, avatar TEXT NOT NULL DEFAULT '🤖',
 color TEXT NOT NULL DEFAULT '#0F766E', persona TEXT NOT NULL DEFAULT '', instructions TEXT NOT NULL DEFAULT '',
 created_at TEXT NOT NULL, allowed_tools TEXT NOT NULL DEFAULT '[]', delegate_to TEXT NOT NULL DEFAULT '[]',
 accept_delegation INTEGER NOT NULL DEFAULT 0, image_updated_at TEXT, memory_access TEXT NOT NULL DEFAULT 'bot_and_global',
 tags TEXT NOT NULL DEFAULT '[]', pinned_at TEXT, UNIQUE(user_id,name));
CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
INSERT INTO schema_meta VALUES ('version','6');
INSERT INTO users VALUES (1,'legacy','x','2026-01-01',NULL,NULL,NULL,1);
INSERT INTO bots(id,user_id,name,created_at,allowed_tools,tags,pinned_at)
 VALUES (1,1,'Old','2026-01-01','["get_weather"]','["研究"]','2026-02-02T00:00:00+00:00');
""")
con.commit(); con.close()

from verabot import db
db.init_db(); db.init_db()
con = sqlite3.connect(DB)
ver = con.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()[0]
tables = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}
legacy = con.execute("SELECT name, allowed_tools, tags, pinned_at FROM bots WHERE id=1").fetchone()
cols = {r[1] for r in con.execute("PRAGMA table_info(mcp_servers)").fetchall()}
con.close()
needed = {"mcp_servers", "mcp_tools", "mcp_credentials", "oauth_states", "pending_actions"}
v8_cols = {"consent_at", "sync_status", "circuit_failures", "circuit_open_until"}
check("MCP-01 migration v6 keeps bots and reaches current (>= v8)",
      ver == str(db.SCHEMA_VERSION) and int(ver) >= 8 and needed <= tables and v8_cols <= cols
      and legacy == ("Old", '["get_weather"]', '["研究"]', "2026-02-02T00:00:00+00:00"),
      f"ver={ver} missing={needed-tables} cols={v8_cols-cols} legacy={legacy}")


class MockMCP(ThreadingHTTPServer):
    allow_reuse_address = True

    def __init__(self, mode="json", session_id="sess-1", server_protocol="2025-03-26", tools=None, delay=0.0):
        self.mode = mode
        self.session_id = session_id
        self.server_protocol = server_protocol
        self.tools = tools or []
        self.delay = delay
        self.requests = []
        # 下列计数由测试线程改、由请求线程读。CPython 下整数赋值可见。
        self.fail_calls = 0            # 接下来这么多次 tools/call 返回 HTTP 500
        self.expire_once = False       # 下一次带当前会话号的 tools/call 或 tools/list 返回 404，并换新会话号
        self.slow_calls = 0            # 接下来这么多次 tools/call 额外睡 call_delay 秒
        self.call_delay = 0.0
        self.is_error_remaining = 0    # 接下来这么多次 tools/call 返回 isError
        self.http_400_remaining = 0    # 接下来这么多次 tools/call 返回 HTTP 400
        super().__init__(("127.0.0.1", 0), _Handler)
        self.thread = threading.Thread(target=self.serve_forever, daemon=True)
        self.thread.start()

    @property
    def url(self):
        return f"http://127.0.0.1:{self.server_address[1]}/mcp"

    def stop(self):
        self.shutdown()
        self.server_close()


class _Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""
        try:
            body = json.loads(raw.decode() or "{}")
        except json.JSONDecodeError:
            body = {"_raw": raw.decode(errors="replace")}
        srv = self.server
        srv.requests.append({
            "accept": self.headers.get("Accept"),
            "session": self.headers.get("Mcp-Session-Id"),
            "protocol": self.headers.get("MCP-Protocol-Version"),
            "body": body,
        })
        if srv.delay:
            time.sleep(srv.delay)
        method = body.get("method")
        if method in ("tools/call", "tools/list") and srv.expire_once:
            sent = self.headers.get("Mcp-Session-Id")
            if sent and sent == srv.session_id:
                srv.expire_once = False
                srv.session_id = (srv.session_id or "sess") + "b"
                self._reply(404, None, send_session=False)
                return
        if method == "tools/call" and srv.fail_calls > 0:
            srv.fail_calls -= 1
            self._reply(500, None, send_session=False)
            return
        if method == "tools/call" and srv.http_400_remaining > 0:
            srv.http_400_remaining -= 1
            self._reply(400, None, send_session=False)
            return
        if method == "tools/call" and srv.slow_calls > 0:
            srv.slow_calls -= 1
            time.sleep(srv.call_delay)
        if method == "notifications/initialized":
            self._reply(202, None)
            return
        if method == "initialize":
            self._reply(200, {"jsonrpc": "2.0", "id": body.get("id"), "result": {
                "protocolVersion": srv.server_protocol,
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "mock", "version": "0"},
            }})
            return
        if method == "tools/list":
            self._reply(200, {"jsonrpc": "2.0", "id": body.get("id"), "result": {"tools": srv.tools}})
            return
        if method == "tools/call":
            name = (body.get("params") or {}).get("name")
            if srv.is_error_remaining > 0:
                srv.is_error_remaining -= 1
                self._reply(200, {"jsonrpc": "2.0", "id": body.get("id"), "result": {
                    "content": [{"type": "text", "text": "nope-secret"}], "isError": True}})
                return
            if name == "rpc-bad":
                self._reply(200, {"jsonrpc": "2.0", "id": body.get("id"),
                                  "error": {"code": -32602, "message": "bad arguments"}})
                return
            if name == "tool-bad":
                self._reply(200, {"jsonrpc": "2.0", "id": body.get("id"), "result": {
                    "content": [{"type": "text", "text": "nope"}], "isError": True}})
                return
            text = "hello"
            if name == "microsoft_docs_fetch":
                text = "# Microsoft Learn MCP Server overview\n"
            self._reply(200, {"jsonrpc": "2.0", "id": body.get("id"), "result": {
                "content": [{"type": "text", "text": text}], "isError": False}})
            return
        self._reply(200, {"jsonrpc": "2.0", "id": body.get("id"),
                          "error": {"code": -32601, "message": "unknown method"}})

    def _reply(self, status, payload, send_session=True):
        srv = self.server
        if payload is None:
            data = b""
            ctype = "application/json"
        elif srv.mode == "sse":
            data = ("event: message\ndata: " + json.dumps(payload) + "\n\n").encode()
            ctype = "text/event-stream"
        else:
            data = json.dumps(payload).encode()
            ctype = "application/json"
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        if send_session and srv.session_id:
            self.send_header("Mcp-Session-Id", srv.session_id)
        self.end_headers()
        if data:
            try:
                self.wfile.write(data)
            except BrokenPipeError:
                return


def _reqs(server, method):
    return [r for r in server.requests if r["body"].get("method") == method]


os.environ["VERABOT_MCP_PROTOCOL_VERSION"] = "2025-06-18"
from verabot.services.mcp.http_client import (
    ACCEPT, MCPProtocolError, MCPRPCError, MCPSession, MCPTimeoutError,
)

TOOLS = [{
    "name": "microsoft_docs_search",
    "description": "Search <script>alert(1)</script> docs",
    "inputSchema": {"type": "object", "properties": {"query": {"type": "string"}}, "required": ["query"]},
}, {
    "name": "code.sample",
    "description": "sample",
    "inputSchema": {"type": "object", "properties": {}},
}, {
    "name": "bad name",
    "description": "nope",
    "inputSchema": {"type": "object"},
}]

for mode in ("json", "sse"):
    mock = MockMCP(mode=mode, session_id="sess-1", server_protocol="2025-03-26", tools=TOOLS)
    try:
        with MCPSession(mock.url, timeout=5) as session:
            version = session.initialize()
            listed = session.list_tools()
            ok = session.call_tool("microsoft_docs_search", {"query": "mcp"})
            bad = session.call_tool("tool-bad", {})
            rpc = None
            try:
                session.call_tool("rpc-bad", {})
            except MCPRPCError as exc:
                rpc = exc
        init = _reqs(mock, "initialize")[0]
        follow = _reqs(mock, "tools/list")[0]
        check(f"MCP-HTTP {mode} accept/session/downgrade",
              version == "2025-03-26"
              and init["accept"] == ACCEPT and init["session"] is None and init["protocol"] is None
              and init["body"]["params"]["protocolVersion"] == "2025-06-18"
              and follow["session"] == "sess-1" and follow["protocol"] == "2025-03-26"
              and follow["accept"] == ACCEPT
              and [t["name"] for t in listed][0] == "microsoft_docs_search"
              and ok.is_error is False and ok.code == "ok" and ok.text == "hello"
              and bad.is_error is True and bad.code == "mcp_tool_error"
              and rpc is not None and rpc.code == "mcp_rpc_error" and "bad arguments" in rpc.message,
              f"version={version} init={init} follow={follow} rpc={rpc}")
    finally:
        mock.stop()

bare = MockMCP(mode="json", session_id=None, server_protocol="2025-06-18", tools=TOOLS[:1])
try:
    with MCPSession(bare.url, timeout=5) as session:
        session.initialize()
        session.list_tools()
    follow = _reqs(bare, "tools/list")[0]
    check("MCP-HTTP omit session when server has none",
          follow["session"] is None and follow["protocol"] == "2025-06-18", str(follow))
finally:
    bare.stop()

high = MockMCP(mode="json", session_id="s", server_protocol="2026-07-28", tools=[])
try:
    raised = False
    try:
        with MCPSession(high.url, timeout=5) as session:
            session.initialize()
    except MCPProtocolError:
        raised = True
    check("MCP-HTTP reject higher protocol", raised)
finally:
    high.stop()

slow = MockMCP(mode="json", session_id=None, delay=1.2, tools=[])
try:
    raised = False
    try:
        with MCPSession(slow.url, timeout=0.3) as session:
            session.initialize()
    except MCPTimeoutError as exc:
        raised = exc.code == "mcp_timeout"
    check("MCP-HTTP timeout", raised)
finally:
    slow.stop()

reuse = MockMCP(mode="json", session_id="sess-a", server_protocol="2025-03-26", tools=TOOLS[:1])
try:
    with MCPSession(reuse.url, timeout=5) as session:
        session.call_tool("microsoft_docs_search", {"query": "1"})
        session.call_tool("microsoft_docs_search", {"query": "2"})
        inits_before = len(_reqs(reuse, "initialize"))
        reuse.expire_once = True
        again = session.call_tool("microsoft_docs_search", {"query": "3"})
    calls = _reqs(reuse, "tools/call")
    inits_after = len(_reqs(reuse, "initialize"))
    check("MCP-SESSION reuse then 404 reinitialize once",
          inits_before == 1 and _reqs(reuse, "initialize")[0]["session"] is None
          and [c["session"] for c in calls[:3]] == ["sess-a", "sess-a", "sess-a"]
          and inits_after == 2 and again.ok and again.text == "hello"
          and calls[-1]["session"] == "sess-ab",
          f"inits {inits_before}->{inits_after} sessions={[c['session'] for c in calls]}")
finally:
    reuse.stop()

flaky = MockMCP(mode="json", session_id="s", server_protocol="2025-03-26", tools=TOOLS[:1])
try:
    from verabot.services.mcp.http_client import MCPUnavailableError
    flaky.fail_calls = 1
    caught = None
    with MCPSession(flaky.url, timeout=5) as session:
        try:
            session.call_tool("microsoft_docs_search", {})
        except MCPUnavailableError as exc:
            caught = exc.code
    check("MCP-HTTP 500 is unavailable and not a tool error", caught == "mcp_unavailable", str(caught))
finally:
    flaky.stop()


def asyncio_run(coro):
    import asyncio
    return asyncio.run(coro)


def _keys(source, type_name):
    import re
    match = re.search(rf"struct {type_name}\b.*?enum CodingKeys: String, CodingKey \{{(.*?)\n    \}}", source, re.S)
    if not match:
        return set()
    found = set()
    for line in match.group(1).splitlines():
        line = line.strip().rstrip(",")
        if not line.startswith("case "):
            continue
        rest = line[len("case "):]
        if "=" in rest:
            found.add(rest.split("=", 1)[1].strip().strip('"'))
        else:
            found.update(part.strip() for part in rest.split(",") if part.strip())
    return found


# ---------- API：假服务器 + 契约 ----------
os.environ["VERABOT_MCP_RETRY_MAX"] = "2"
os.environ["VERABOT_MCP_RETRY_BACKOFF"] = "0,0"
os.environ["VERABOT_MCP_BREAKER_THRESHOLD"] = "5"
os.environ["VERABOT_MCP_BREAKER_COOLDOWN"] = "60"
api_mock = MockMCP(mode="sse", session_id="api-sess", server_protocol="2025-03-26", tools=TOOLS, delay=1.2)
os.environ["VERABOT_MCP_LEARN_URL"] = api_mock.url
os.environ["VERABOT_MCP_AWS_URL"] = "http://127.0.0.1:9/mcp"
try:
    from fastapi.testclient import TestClient
    from verabot.main import app
    cli = TestClient(app)
    token = cli.post("/api/auth/register", json={"username": "mcpuser", "password": "pw123456"}).json()["token"]
    H = {"Authorization": "Bearer " + token}

    def learn_row():
        body = cli.get("/api/mcp/servers", headers=H).json()
        return next(s for s in body["servers"] if s["slug"] == "learn"), next(s for s in body["servers"] if s["slug"] == "aws")

    t0 = time.perf_counter()
    servers = cli.get("/api/mcp/servers", headers=H)
    elapsed = time.perf_counter() - t0
    learn, aws = learn_row()
    check("MCP-SYNC GET does not wait for the network",
          servers.status_code == 200 and elapsed < 0.7
          and learn["sync_status"] in ("pending", "syncing")
          and "url" not in learn and aws["status"] == "disabled",
          f"elapsed={elapsed:.3f} learn={learn.get('sync_status')} {servers.text[:300]}")
    api_mock.delay = 0

    def wait_learn(timeout=8):
        deadline = time.time() + timeout
        last = None
        while time.time() < deadline:
            last, _aws = learn_row()
            if last["sync_status"] in ("ok", "error"):
                return last
            time.sleep(0.05)
        return last

    learn = wait_learn()
    inits = _reqs(api_mock, "initialize")
    check("MCP-API default learn connected, aws disabled, no aws traffic",
          learn["status"] == "connected" and learn["sync_status"] == "ok" and learn["enabled"] is True
          and aws["status"] == "disabled" and aws["enabled"] is False and len(inits) == 1
          and learn["circuit_state"] == "closed" and learn["consent_at"] is None,
          str({k: learn.get(k) for k in ("status", "sync_status", "circuit_state", "consent_at")}) + f" inits={len(inits)}")
    tools = cli.get(f"/api/mcp/servers/{learn['id']}/tools", headers=H).json()["tools"]
    names = {t["mcp_name"]: t for t in tools}
    check("MCP-02 namespace and illegal tool dropped",
          "microsoft_docs_search" in names and names["microsoft_docs_search"]["full_name"] == "mcp__learn__microsoft_docs_search"
          and names["code.sample"]["full_name"] == "mcp__learn__code_sample"
          and "bad name" not in names and names["microsoft_docs_search"]["risk"] == "read",
          str([(t["mcp_name"], t["full_name"], t["risk"]) for t in tools]))
    bot = cli.post("/api/bots", json={"name": "Vera"}, headers=H).json()
    check("MCP-04 new bot has no MCP tools", bot["allowed_tools"] == [], str(bot.get("allowed_tools")))
    full = names["microsoft_docs_search"]["full_name"]
    patched = cli.patch(f"/api/bots/{bot['id']}", json={"allowed_tools": [full, "get_weather"]}, headers=H)
    check("MCP-04 save concrete tool name",
          patched.status_code == 200 and full in patched.json()["allowed_tools"], patched.text[:300])
    unknown = cli.patch(f"/api/bots/{bot['id']}", json={"allowed_tools": ["mcp__learn__nope"]}, headers=H)
    check("MCP-04 unknown mcp tool 422", unknown.status_code == 422 and "未知工具" in unknown.text, unknown.text[:200])

    from verabot.agents.tool_router import dispatch
    from verabot.tools.registry import ToolContext, TurnState
    me = cli.get("/api/me", headers=H).json()
    fresh = db.get_bot(me["id"], bot["id"])
    ctx = ToolContext(user_id=me["id"], bot=fresh, depth=0, turn=TurnState())
    calls_before = len(_reqs(api_mock, "tools/call"))
    refused = asyncio_run(dispatch(ctx, full, '{"query":"mcp"}', call_id="c_no"))
    check("MCP-CONSENT blocks calls until granted",
          refused.get("code") == "mcp_consent_required" and "DeepSeek" in refused.get("error", "")
          and len(_reqs(api_mock, "tools/call")) == calls_before and ctx.turn.untrusted_tainted is False,
          str(refused)[:300])
    granted = cli.post(f"/api/mcp/servers/{learn['id']}/consent", json={"granted": True}, headers=H)
    check("MCP-CONSENT grant stores timestamp",
          granted.status_code == 200 and isinstance(granted.json().get("consent_at"), str)
          and granted.json()["consent_at"],
          granted.text[:240])
    consent_at = granted.json()["consent_at"]
    called = asyncio_run(dispatch(ctx, full, '{"query":"mcp"}', call_id="c_read"))
    check("MCP-CALL read tool wrapped",
          called.get("code") == "ok" and "untrusted_tool_result" in called.get("content", "")
          and "<script>" not in called.get("content", "") and ctx.turn.untrusted_tainted is True,
          str(called)[:400])
    inits_after_calls = len(_reqs(api_mock, "initialize"))
    second = asyncio_run(dispatch(ToolContext(user_id=me["id"], bot=fresh, depth=0, turn=TurnState()), full, '{"query":"2"}', call_id="c_2"))
    check("MCP-SESSION pool reuses Mcp-Session-Id",
          second.get("code") == "ok" and len(_reqs(api_mock, "initialize")) == inits_after_calls == 1
          and _reqs(api_mock, "tools/call")[-1]["session"] == "api-sess",
          f"inits={len(_reqs(api_mock, 'initialize'))} session={_reqs(api_mock, 'tools/call')[-1]['session']}")
    api_mock.expire_once = True
    retried = asyncio_run(dispatch(ToolContext(user_id=me["id"], bot=fresh, depth=0, turn=TurnState()), full, '{"query":"3"}', call_id="c_404"))
    check("MCP-SESSION 404 reinitializes once and succeeds",
          retried.get("code") == "ok" and len(_reqs(api_mock, "initialize")) == 2
          and _reqs(api_mock, "tools/call")[-1]["session"] == "api-sessb",
          f"inits={len(_reqs(api_mock, 'initialize'))} code={retried.get('code')}")
    denied = asyncio_run(dispatch(ctx, full, '{"query":"x"}'))
    # still allowed; second call is fine. Check not-allowed on a copy without the tool.
    bare_bot = {**fresh, "allowed_tools": []}
    denied = asyncio_run(dispatch(ToolContext(user_id=me["id"], bot=bare_bot, depth=0, turn=TurnState()), full, "{}"))
    check("MCP-05 not in allowlist", denied.get("code") == "tool_not_allowed", str(denied))
    delegated = asyncio_run(dispatch(ToolContext(user_id=me["id"], bot=fresh, depth=1, turn=TurnState()), full, "{}"))
    check("MCP-07 delegated bot cannot call MCP", delegated.get("code") == "not_delegable", str(delegated))
    from verabot.agents.guardrails import check_delegation
    other = cli.post("/api/bots", json={"name": "Other", "accept_delegation": True}, headers=H).json()
    ctx.bot = {**fresh, "delegate_to": [other["id"]]}
    other_row = db.get_bot(me["id"], other["id"])
    rejection = check_delegation(ctx, other_row)
    check("MCP-08 taint blocks ask_bot", rejection is not None and rejection.reason == "untrusted_tainted", str(rejection))

    # 长结果：MCP 结果已在 sanitize 里截到 VERABOT_MCP_MAX_RESULT_CHARS (默认 8000)，tool 消息不能再按 6000 字截断，
    # 否则会切掉 </untrusted_tool_result>（真实 Learn 搜索一次返回约 3.6 万字）。
    import json as _json
    from verabot.agents.runtime import _tool_content
    from verabot.services.mcp.sanitize import wrap
    long_wrapped, long_cut = wrap("learn", "microsoft_docs_search", "c1", "文" * 20000)
    mcp_msg = _tool_content(full, {"content": long_wrapped, "code": "ok"})
    builtin_msg = _tool_content("get_weather", {"text": "x" * 9000})
    check("MCP-CALL long result keeps closing marker",
          long_cut and _json.loads(mcp_msg)["content"].endswith("</untrusted_tool_result>") and len(builtin_msg) == 6000,
          f"len={len(mcp_msg)} builtin={len(builtin_msg)}")

    def call_rows():
        con = sqlite3.connect(DB)
        con.row_factory = sqlite3.Row
        rows = con.execute(
            "SELECT user_id, bot_id, detail FROM audit_log WHERE kind='mcp_tool_call' ORDER BY id"
        ).fetchall()
        con.close()
        return rows

    def detail_ok(row):
        text = row["detail"]
        data = json.loads(text)
        leaked = "hello" in text or "nope-secret" in text or "untrusted_tool_result" in text or "文文" in text
        return (not leaked) and data.get("tool") and data.get("server") and "duration_ms" in data \
            and data.get("started_at") and data.get("finished_at") and row["user_id"] == me["id"]

    audit_rows = call_rows()
    by_call = {json.loads(r["detail"]).get("call_id"): json.loads(r["detail"]) for r in audit_rows}
    check("MCP-AUDIT every call, no raw content",
          all(detail_ok(r) for r in audit_rows)
          and by_call["c_no"]["error_class"] == "mcp_consent_required" and by_call["c_no"]["status"] == "error"
          and by_call["c_read"]["status"] == "ok" and by_call["c_read"]["error_class"] is None
          and all(r["bot_id"] == bot["id"] for r in audit_rows),
          str({k: (v.get("status"), v.get("error_class")) for k, v in by_call.items()}))

    calls_now = len(_reqs(api_mock, "tools/call"))
    api_mock.is_error_remaining = 1
    tool_err = asyncio_run(dispatch(ToolContext(user_id=me["id"], bot=fresh, depth=0, turn=TurnState()), full, "{}", call_id="c_iserr"))
    check("MCP-RETRY tool isError is not retried",
          tool_err.get("code") == "mcp_tool_error" and len(_reqs(api_mock, "tools/call")) == calls_now + 1
          and "nope-secret" not in json.dumps(call_rows()[-1]["detail"]),
          str(tool_err)[:200])

    calls_now = len(_reqs(api_mock, "tools/call"))
    api_mock.http_400_remaining = 1
    http400 = asyncio_run(dispatch(ToolContext(user_id=me["id"], bot=fresh, depth=0, turn=TurnState()), full, "{}", call_id="c_400"))
    check("MCP-RETRY HTTP 400 is not retried",
          http400.get("code") == "mcp_protocol" and len(_reqs(api_mock, "tools/call")) == calls_now + 1,
          str(http400)[:200])

    calls_now = len(_reqs(api_mock, "tools/call"))
    api_mock.fail_calls = 2
    recovered = asyncio_run(dispatch(ToolContext(user_id=me["id"], bot=fresh, depth=0, turn=TurnState()), full, "{}", call_id="c_500"))
    check("MCP-RETRY 5xx then success within limit",
          recovered.get("code") == "ok" and len(_reqs(api_mock, "tools/call")) == calls_now + 3 and api_mock.fail_calls == 0,
          f"code={recovered.get('code')} calls={len(_reqs(api_mock, 'tools/call')) - calls_now}")

    os.environ["VERABOT_MCP_TIMEOUT"] = "0.15"
    calls_now = len(_reqs(api_mock, "tools/call"))
    api_mock.slow_calls = 1
    api_mock.call_delay = 0.45
    from verabot.services.mcp import service as mcp_service
    import verabot.db.mcp_store as mcp_store
    tool_row = mcp_store.get_tool_by_full_name(me["id"], full)
    server_row = mcp_store.get_server(me["id"], learn["id"])
    write_tool = {**tool_row, "risk": "write", "annotations": {}}
    unknown = mcp_service.invoke(me["id"], server_row, write_tool, {"query": "x"}, call_id="c_unknown", bot_id=bot["id"])
    check("MCP-RETRY non-idempotent timeout is result_unknown and not retried",
          unknown.get("code") == "result_unknown" and len(_reqs(api_mock, "tools/call")) == calls_now + 1,
          str(unknown)[:240])
    os.environ["VERABOT_MCP_RETRY_MAX"] = "0"
    calls_zero = len(_reqs(api_mock, "tools/call"))
    api_mock.slow_calls = 1
    unknown0 = mcp_service.invoke(me["id"], server_row, write_tool, {"query": "y"}, call_id="c_unknown0", bot_id=bot["id"])
    os.environ["VERABOT_MCP_RETRY_MAX"] = "2"
    check("MCP-RETRY non-idempotent timeout is result_unknown even with RETRY_MAX=0",
          unknown0.get("code") == "result_unknown" and len(_reqs(api_mock, "tools/call")) == calls_zero + 1,
          str(unknown0)[:240])
    calls_now = len(_reqs(api_mock, "tools/call")) - 1
    api_mock.slow_calls = 1
    retried_to = asyncio_run(dispatch(ToolContext(user_id=me["id"], bot=fresh, depth=0, turn=TurnState()), full, "{}", call_id="c_timeout"))
    os.environ["VERABOT_MCP_TIMEOUT"] = "5"
    check("MCP-RETRY read timeout then success",
          retried_to.get("code") == "ok" and len(_reqs(api_mock, "tools/call")) == calls_now + 1 + 2,
          f"code={retried_to.get('code')} extra={len(_reqs(api_mock, 'tools/call')) - calls_now}")

    revoked = cli.post(f"/api/mcp/servers/{learn['id']}/consent", json={"granted": False}, headers=H)
    calls_now = len(_reqs(api_mock, "tools/call"))
    after_revoke = asyncio_run(dispatch(ToolContext(user_id=me["id"], bot=fresh, depth=0, turn=TurnState()), full, "{}", call_id="c_revoke"))
    check("MCP-CONSENT revoke stops calls and clears timestamp",
          revoked.status_code == 200 and revoked.json()["consent_at"] is None
          and after_revoke.get("code") == "mcp_consent_required"
          and len(_reqs(api_mock, "tools/call")) == calls_now
          and consent_at != "",
          revoked.text[:200])
    cli.post(f"/api/mcp/servers/{learn['id']}/consent", json={"granted": True}, headers=H)

    aws_id = aws["id"]
    turned = cli.patch(f"/api/mcp/servers/{aws_id}", json={"enabled": False}, headers=H)
    check("MCP-06 disable stays disabled", turned.status_code == 200 and turned.json()["status"] == "disabled", turned.text[:200])

    other_tok = cli.post("/api/auth/register", json={"username": "mcpother", "password": "pw123456"}).json()["token"]
    H2 = {"Authorization": "Bearer " + other_tok}
    foreign = cli.get(f"/api/mcp/servers/{learn['id']}/tools", headers=H2)
    foreign_consent = cli.post(f"/api/mcp/servers/{learn['id']}/consent", json={"granted": True}, headers=H2)
    check("MCP-25 other user 404",
          foreign.status_code == 404 and foreign_consent.status_code == 404, foreign.text[:200])

    # 前后端字段名
    core = (IOS / "VeraBotCore/MCP.swift").read_text()
    models = (IOS / "VeraBotCore/Models.swift").read_text()
    catalog = cli.get("/api/mcp/catalog", headers=H).json()["catalog"][0]
    server_json, _aws_now = learn_row()
    tool_json = names["microsoft_docs_search"]
    builtin = next(t for t in cli.get("/api/tools", headers=H).json()["tools"] if t["name"] == "get_weather")
    mcp_tool_on_tools = next(t for t in cli.get("/api/tools", headers=H).json()["tools"] if t["name"] == full)
    check("MCP-CONTRACT catalog/server/tool/ToolInfo keys",
          _keys(core, "MCPCatalogItem") <= set(catalog)
          and _keys(core, "MCPServer") <= set(server_json)
          and _keys(core, "MCPTool") <= set(tool_json)
          and _keys(models, "ToolInfo") <= set(builtin)
          and _keys(models, "ToolInfo") <= set(mcp_tool_on_tools)
          and mcp_tool_on_tools["source"] == "mcp" and builtin["source"] == "builtin",
          f"catalog missing {_keys(core,'MCPCatalogItem')-set(catalog)} "
          f"server missing {_keys(core,'MCPServer')-set(server_json)} "
          f"tool missing {_keys(core,'MCPTool')-set(tool_json)} "
          f"info missing {_keys(models,'ToolInfo')-set(mcp_tool_on_tools)}")

    os.environ["VERABOT_MCP_BREAKER_THRESHOLD"] = "2"
    os.environ["VERABOT_MCP_BREAKER_COOLDOWN"] = "0.4"
    os.environ["VERABOT_MCP_RETRY_MAX"] = "0"
    api_mock.fail_calls = 8
    b1 = asyncio_run(dispatch(ToolContext(user_id=me["id"], bot=fresh, depth=0, turn=TurnState()), full, "{}", call_id="c_b1"))
    b2 = asyncio_run(dispatch(ToolContext(user_id=me["id"], bot=fresh, depth=0, turn=TurnState()), full, "{}", call_id="c_b2"))
    opened, _ = learn_row()
    quiet = api_mock.fail_calls
    b3 = asyncio_run(dispatch(ToolContext(user_id=me["id"], bot=fresh, depth=0, turn=TurnState()), full, "{}", call_id="c_b3"))
    check("MCP-BREAKER opens after consecutive failures and skips the network",
          b1.get("code") == "mcp_unavailable" and b2.get("code") == "mcp_unavailable"
          and opened["circuit_state"] == "open" and opened["consecutive_failures"] >= 2
          and opened["circuit_open_until"] and b3.get("code") == "mcp_circuit_open"
          and api_mock.fail_calls == quiet,
          f"b1={b1.get('code')} b2={b2.get('code')} b3={b3.get('code')} state={opened.get('circuit_state')} left={api_mock.fail_calls}")
    time.sleep(0.5)
    api_mock.fail_calls = 0
    half, _ = learn_row()
    probed = asyncio_run(dispatch(ToolContext(user_id=me["id"], bot=fresh, depth=0, turn=TurnState()), full, "{}", call_id="c_half"))
    closed, _ = learn_row()
    check("MCP-BREAKER half-open probe closes the circuit",
          half["circuit_state"] == "half_open" and probed.get("code") == "ok"
          and closed["circuit_state"] == "closed" and closed["consecutive_failures"] == 0,
          f"half={half.get('circuit_state')} probed={probed.get('code')} closed={closed.get('circuit_state')} n={closed.get('consecutive_failures')}")
finally:
    api_mock.stop()


def fresh_db():
    import subprocess
    script = r"""
import os, sqlite3, tempfile
from pathlib import Path
td = tempfile.mkdtemp(prefix="vb_mcp_fresh_")
os.environ["VERABOT_DB"] = str(Path(td)/"f.db")
os.environ["VERABOT_DATA_DIR"] = td
os.environ["DEEPSEEK_API_KEY"] = "x"
import sys
sys.path.insert(0, %r)
from verabot import db
db.init_db(); db.init_db()
c = sqlite3.connect(os.environ["VERABOT_DB"])
ver = c.execute("select value from schema_meta where key='version'").fetchone()[0]
tables = {r[0] for r in c.execute("select name from sqlite_master where type='table'")}
bots = c.execute("select count(*) from bots").fetchone()[0]
cols = {r[1] for r in c.execute("pragma table_info(mcp_servers)")}
assert int(ver) >= 8, ver  # v9 起为账号表；MCP 列从 v8 开始存在
assert {"mcp_servers","mcp_tools"} <= tables
assert {"consent_at","sync_status","circuit_failures","circuit_open_until"} <= cols
assert bots == 0
print("fresh", ver)
""" % str(ROOT)
    out = subprocess.check_output([sys.executable, "-c", script], text=True)
    return "fresh " in out


def migrated_v7():
    """已有 v7 库（含服务器与工具行）升到 v8：数据还在，新列就位，同意时间为空。"""
    import subprocess
    script = r"""
import os, sqlite3, tempfile
from pathlib import Path
td = tempfile.mkdtemp(prefix="vb_mcp_v7_")
dbp = str(Path(td)/"v7.db")
os.environ["VERABOT_DB"] = dbp
os.environ["VERABOT_DATA_DIR"] = td
os.environ["DEEPSEEK_API_KEY"] = "x"
c = sqlite3.connect(dbp)
c.executescript('''
CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT UNIQUE NOT NULL, password_hash TEXT NOT NULL,
 created_at TEXT NOT NULL, token_budget INTEGER, nickname TEXT, avatar_updated_at TEXT, memory_enabled INTEGER DEFAULT 1);
CREATE TABLE bots (id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL, name TEXT NOT NULL, avatar TEXT NOT NULL DEFAULT 'x',
 color TEXT NOT NULL DEFAULT '#0F766E', persona TEXT NOT NULL DEFAULT '', instructions TEXT NOT NULL DEFAULT '',
 created_at TEXT NOT NULL, allowed_tools TEXT NOT NULL DEFAULT '[]', delegate_to TEXT NOT NULL DEFAULT '[]',
 accept_delegation INTEGER NOT NULL DEFAULT 0, image_updated_at TEXT, memory_access TEXT NOT NULL DEFAULT 'bot_and_global',
 tags TEXT NOT NULL DEFAULT '[]', pinned_at TEXT, UNIQUE(user_id,name));
CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
INSERT INTO schema_meta VALUES ('version','7');
INSERT INTO users VALUES (1,'legacy','x','2026-01-01',NULL,'小王',NULL,1);
INSERT INTO bots(id,user_id,name,created_at,allowed_tools,tags,pinned_at)
 VALUES (1,1,'Old','2026-01-01','["get_weather","mcp__learn__microsoft_docs_search"]','["研究"]','2026-02-02T00:00:00+00:00');
CREATE TABLE mcp_servers (
  id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL, slug TEXT NOT NULL, source TEXT NOT NULL,
  catalog_id TEXT, name TEXT NOT NULL, transport TEXT NOT NULL, url TEXT, trust TEXT NOT NULL,
  auth_type TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'needs_auth', account_label TEXT,
  granted_scopes TEXT, discover_json TEXT, last_synced_at TEXT, last_error TEXT,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL, UNIQUE(user_id, slug));
CREATE TABLE mcp_tools (
  id INTEGER PRIMARY KEY, server_id INTEGER NOT NULL, user_id INTEGER NOT NULL, mcp_name TEXT NOT NULL,
  full_name TEXT NOT NULL, title TEXT, description TEXT NOT NULL, input_schema TEXT NOT NULL,
  output_schema TEXT, annotations TEXT, def_hash TEXT NOT NULL, accepted_hash TEXT,
  risk TEXT NOT NULL, confirm_policy TEXT NOT NULL DEFAULT 'default', status TEXT NOT NULL DEFAULT 'active',
  first_seen_at TEXT NOT NULL, last_seen_at TEXT NOT NULL);
INSERT INTO mcp_servers(id,user_id,slug,source,catalog_id,name,transport,url,trust,auth_type,status,last_synced_at,created_at,updated_at)
 VALUES (3,1,'learn','catalog','microsoft_learn','Microsoft Learn','streamable_http','http://example.test/mcp','verified','none','connected','2026-10-03T01:00:00+00:00','2026-10-01T00:00:00+00:00','2026-10-03T01:00:00+00:00');
INSERT INTO mcp_servers(id,user_id,slug,source,catalog_id,name,transport,trust,auth_type,status,last_error,created_at,updated_at)
 VALUES (4,1,'aws','catalog','aws_knowledge','AWS Knowledge','streamable_http','verified','none','error','boom','2026-10-01T00:00:00+00:00','2026-10-01T00:00:00+00:00');
INSERT INTO mcp_tools(id,server_id,user_id,mcp_name,full_name,description,input_schema,def_hash,risk,status,first_seen_at,last_seen_at)
 VALUES (9,3,1,'microsoft_docs_search','mcp__learn__microsoft_docs_search','d','{}','abc','read','active','2026-10-03T01:00:00+00:00','2026-10-03T01:00:00+00:00');
''')
c.commit(); c.close()
import sys
sys.path.insert(0, %r)
from verabot import db
db.init_db(); db.init_db()
c = sqlite3.connect(dbp)
ver = c.execute("select value from schema_meta where key='version'").fetchone()[0]
bot = c.execute("select allowed_tools, tags, pinned_at from bots where id=1").fetchone()
learn = c.execute("select status, last_synced_at, consent_at, sync_status, circuit_failures from mcp_servers where id=3").fetchone()
aws = c.execute("select status, sync_status, last_error from mcp_servers where id=4").fetchone()
tool = c.execute("select full_name, risk from mcp_tools where id=9").fetchone()
nick = c.execute("select nickname from users where id=1").fetchone()[0]
assert int(ver) >= 8, ver  # v9 起为账号表；MCP 列从 v8 开始存在
assert bot == ('["get_weather","mcp__learn__microsoft_docs_search"]', '["研究"]', "2026-02-02T00:00:00+00:00"), bot
assert learn[0] == "connected" and learn[1] == "2026-10-03T01:00:00+00:00" and learn[2] is None and learn[3] == "ok" and learn[4] == 0, learn
assert aws == ("error", "error", "boom"), aws
assert tool == ("mcp__learn__microsoft_docs_search", "read"), tool
assert nick == "小王"
print("v7ok", ver)
""" % str(ROOT)
    out = subprocess.check_output([sys.executable, "-c", script], text=True)
    return "v7ok " in out


check("MCP-01 fresh database is current (>= v8)", fresh_db())
check("MCP-01 migration v7 keeps servers, tools and consent is empty", migrated_v7())


def live():
    if os.getenv("VERABOT_MCP_LIVE_TESTS") != "1":
        print("SKIP MCP-LIVE Microsoft Learn + AWS Knowledge (set VERABOT_MCP_LIVE_TESTS=1)")
        return
    if ORIG_LEARN is None:
        os.environ.pop("VERABOT_MCP_LEARN_URL", None)
    else:
        os.environ["VERABOT_MCP_LEARN_URL"] = ORIG_LEARN
    if ORIG_AWS is None:
        os.environ.pop("VERABOT_MCP_AWS_URL", None)
    else:
        os.environ["VERABOT_MCP_AWS_URL"] = ORIG_AWS
    from verabot.services.mcp.catalog import entries
    urls = {item["catalog_id"]: item["url"] for item in entries()}
    with MCPSession(urls["microsoft_learn"], timeout=15) as session:
        result = session.call_tool("microsoft_docs_fetch", {"url": "https://learn.microsoft.com/en-us/training/support/mcp"})
    text = result.text.lstrip()
    check("MCP-LIVE learn fetch", result.is_error is False and text.startswith("# Microsoft Learn MCP Server overview"), text[:180])
    with MCPSession(urls["aws_knowledge"], timeout=15) as session:
        regions = session.call_tool("aws___list_regions", {})
    compact = "".join(regions.text.split())
    check("MCP-LIVE aws regions", regions.is_error is False and '"region_id":"af-south-1"' in compact, regions.text[:180])


live()
print(f"\nMCP tests failed: {len(FAILS)}")
sys.exit(1 if FAILS else 0)
