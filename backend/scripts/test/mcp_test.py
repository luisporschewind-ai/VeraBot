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
con.close()
needed = {"mcp_servers", "mcp_tools", "mcp_credentials", "oauth_states", "pending_actions"}
check("MCP-01 migration v6 keeps bots and reaches v7",
      ver == "7" == str(db.SCHEMA_VERSION) and needed <= tables
      and legacy == ("Old", '["get_weather"]', '["研究"]', "2026-02-02T00:00:00+00:00"),
      f"ver={ver} missing={needed-tables} legacy={legacy}")


class MockMCP(ThreadingHTTPServer):
    allow_reuse_address = True

    def __init__(self, mode="json", session_id="sess-1", server_protocol="2025-03-26", tools=None, delay=0.0):
        self.mode = mode
        self.session_id = session_id
        self.server_protocol = server_protocol
        self.tools = tools or []
        self.delay = delay
        self.requests = []
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

    def _reply(self, status, payload):
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
        if srv.session_id:
            self.send_header("Mcp-Session-Id", srv.session_id)
        self.end_headers()
        if data:
            self.wfile.write(data)


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
api_mock = MockMCP(mode="sse", session_id="api-sess", server_protocol="2025-03-26", tools=TOOLS)
os.environ["VERABOT_MCP_LEARN_URL"] = api_mock.url
os.environ["VERABOT_MCP_AWS_URL"] = "http://127.0.0.1:9/mcp"
try:
    from fastapi.testclient import TestClient
    from verabot.main import app
    cli = TestClient(app)
    token = cli.post("/api/auth/register", json={"username": "mcpuser", "password": "pw123456"}).json()["token"]
    H = {"Authorization": "Bearer " + token}
    servers = cli.get("/api/mcp/servers", headers=H)
    body = servers.json()
    learn = next(s for s in body["servers"] if s["slug"] == "learn")
    aws = next(s for s in body["servers"] if s["slug"] == "aws")
    inits = _reqs(api_mock, "initialize")
    check("MCP-API default learn connected, aws disabled, no aws traffic",
          servers.status_code == 200 and learn["status"] == "connected" and learn["enabled"] is True
          and aws["status"] == "disabled" and aws["enabled"] is False and len(inits) == 1,
          servers.text[:500])
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
    bot_row = db.get_bot(int(bot["user_id"]) if False else None, bot["id"]) if False else None
    # get_bot needs user id from the token's user, not the legacy row
    me = cli.get("/api/me", headers=H).json()
    fresh = db.get_bot(me["id"], bot["id"])
    ctx = ToolContext(user_id=me["id"], bot=fresh, depth=0, turn=TurnState())
    called = asyncio_run(dispatch(ctx, full, '{"query":"mcp"}'))
    check("MCP-CALL read tool wrapped",
          called.get("code") == "ok" and "untrusted_tool_result" in called.get("content", "")
          and "<script>" not in called.get("content", "") and ctx.turn.untrusted_tainted is True,
          str(called)[:400])
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

    aws_id = aws["id"]
    turned = cli.patch(f"/api/mcp/servers/{aws_id}", json={"enabled": False}, headers=H)
    check("MCP-06 disable stays disabled", turned.status_code == 200 and turned.json()["status"] == "disabled", turned.text[:200])

    other_tok = cli.post("/api/auth/register", json={"username": "mcpother", "password": "pw123456"}).json()["token"]
    H2 = {"Authorization": "Bearer " + other_tok}
    foreign = cli.get(f"/api/mcp/servers/{learn['id']}/tools", headers=H2)
    check("MCP-25 other user 404", foreign.status_code == 404, foreign.text[:200])

    # 前后端字段名
    core = (IOS / "VeraBotCore/MCP.swift").read_text()
    models = (IOS / "VeraBotCore/Models.swift").read_text()
    catalog = cli.get("/api/mcp/catalog", headers=H).json()["catalog"][0]
    server_json = learn
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
assert ver == "7", ver
assert {"mcp_servers","mcp_tools"} <= tables
assert bots == 0
print("fresh", ver)
""" % str(ROOT)
    out = subprocess.check_output([sys.executable, "-c", script], text=True)
    return "fresh 7" in out


check("MCP-01 fresh database is v7", fresh_db())


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
