#!/usr/bin/env python3
"""插件 P1：迁移、安装 / 卸载、派生状态、契约。进程内假 MCP 服务器，不访问外网。"""
import json, os, sqlite3, sys, tempfile, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TMP = tempfile.mkdtemp(prefix="vb_plugin_")
DB = str(Path(TMP) / "t.db")
os.environ["VERABOT_DB"] = DB
os.environ["VERABOT_DATA_DIR"] = TMP
os.environ.setdefault("DEEPSEEK_API_KEY", "test-not-used")
os.environ["VERABOT_MCP_AWS_ENABLED"] = "0"
os.environ["VERABOT_MCP_LEARN_ENABLED"] = "1"
os.environ["VERABOT_MCP_RETRY_MAX"] = "2"
os.environ["VERABOT_MCP_RETRY_BACKOFF"] = "0,0"
os.environ["VERABOT_MCP_BREAKER_THRESHOLD"] = "5"
os.environ["VERABOT_MCP_BREAKER_COOLDOWN"] = "60"
sys.path.insert(0, str(ROOT))

IOS = ROOT.parent / "frontend/ios/Packages/VeraBotKit/Sources"
FAILS = []


def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else " " + detail))
    if not ok:
        FAILS.append(name)


class MockMCP(ThreadingHTTPServer):
    allow_reuse_address = True

    def __init__(self, tools=None, list_delay=0.0, call_delay=0.0):
        self.tools = tools if tools is not None else [{
            "name": "microsoft_docs_search",
            "description": "Search docs",
            "inputSchema": {"type": "object", "properties": {"query": {"type": "string"}}},
        }]
        self.list_delay = list_delay
        self.call_delay = call_delay
        self.calls = 0
        self.lists = 0
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
        raw = self.rfile.read(length) if length else b"{}"
        try:
            body = json.loads(raw.decode() or "{}")
        except json.JSONDecodeError:
            body = {}
        method = body.get("method")
        srv = self.server
        if method == "tools/list":
            srv.lists += 1
            if srv.list_delay:
                time.sleep(srv.list_delay)
        if method == "tools/call":
            srv.calls += 1
            if srv.call_delay:
                time.sleep(srv.call_delay)
        if method == "notifications/initialized":
            self._reply(202, None)
            return
        if method == "initialize":
            self._reply(200, {"jsonrpc": "2.0", "id": body.get("id"), "result": {
                "protocolVersion": "2025-03-26",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "mock", "version": "0"},
            }})
            return
        if method == "tools/list":
            self._reply(200, {"jsonrpc": "2.0", "id": body.get("id"), "result": {"tools": srv.tools}})
            return
        if method == "tools/call":
            self._reply(200, {"jsonrpc": "2.0", "id": body.get("id"), "result": {
                "content": [{"type": "text", "text": "hello"}], "isError": False}})
            return
        self._reply(200, {"jsonrpc": "2.0", "id": body.get("id"), "error": {"code": -32601, "message": "no"}})

    def _reply(self, status, payload):
        data = b"" if payload is None else json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Mcp-Session-Id", "plug-sess")
        self.end_headers()
        if data:
            try:
                self.wfile.write(data)
            except BrokenPipeError:
                return


def _keys(source, type_name):
    import re
    match = re.search(rf"(?:struct|enum) {type_name}\b.*?enum CodingKeys: String, CodingKey \{{(.*?)\n    \}}", source, re.S)
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


def migrate(label, version, body_sql):
    """在子进程里从指定版本迁到当前版本，各启动两次。"""
    import subprocess
    td = tempfile.mkdtemp(prefix=f"vb_plg_{label}_")
    dbp = str(Path(td) / "m.db")
    script = r'''
import os, sqlite3, sys
os.environ["VERABOT_DB"] = %r
os.environ["VERABOT_DATA_DIR"] = %r
os.environ["DEEPSEEK_API_KEY"] = "x"
sys.path.insert(0, %r)
c = sqlite3.connect(os.environ["VERABOT_DB"])
c.executescript(%r)
c.commit(); c.close()
from verabot import db
db.init_db(); db.init_db()
c = sqlite3.connect(os.environ["VERABOT_DB"])
ver = c.execute("select value from schema_meta where key='version'").fetchone()[0]
tables = {r[0] for r in c.execute("select name from sqlite_master where type='table'")}
cols = {r[1] for r in c.execute("pragma table_info(mcp_servers)")} if "mcp_servers" in tables else set()
plugins = c.execute("select user_id, plugin_id, status from user_plugins order by user_id, plugin_id").fetchall()
learn = c.execute("select plugin_id, consent_at from mcp_servers where slug='learn'").fetchone() if "mcp_servers" in tables else None
bots = c.execute("select allowed_tools from bots order by id").fetchall() if "bots" in tables else []
tomb = c.execute("select count(*) from user_plugins where status='uninstalled'").fetchone()[0]
n1 = len(plugins)
db.init_db()
c = sqlite3.connect(os.environ["VERABOT_DB"])
n2 = c.execute("select count(*) from user_plugins").fetchone()[0]
import json
print(json.dumps({
  "ver": ver, "has_plugins": "user_plugins" in tables, "has_plugin_id": "plugin_id" in cols,
  "plugins": [list(r) for r in plugins], "learn": list(learn) if learn else None,
  "bots": [r[0] for r in bots], "tomb": tomb, "n1": n1, "n2": n2,
}, ensure_ascii=False))
''' % (dbp, td, str(ROOT), body_sql)
    out = subprocess.check_output([sys.executable, "-c", script], text=True).strip().splitlines()[-1]
    return json.loads(out)


BASE_V8 = """
CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT UNIQUE NOT NULL, password_hash TEXT NOT NULL,
 created_at TEXT NOT NULL, token_budget INTEGER, nickname TEXT, avatar_updated_at TEXT, memory_enabled INTEGER DEFAULT 1);
CREATE TABLE bots (id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL, name TEXT NOT NULL, avatar TEXT NOT NULL DEFAULT 'x',
 color TEXT NOT NULL DEFAULT '#0F766E', persona TEXT NOT NULL DEFAULT '', instructions TEXT NOT NULL DEFAULT '',
 created_at TEXT NOT NULL, allowed_tools TEXT NOT NULL DEFAULT '[]', delegate_to TEXT NOT NULL DEFAULT '[]',
 accept_delegation INTEGER NOT NULL DEFAULT 0, image_updated_at TEXT, memory_access TEXT NOT NULL DEFAULT 'bot_and_global',
 tags TEXT NOT NULL DEFAULT '[]', pinned_at TEXT, UNIQUE(user_id,name));
CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
INSERT INTO schema_meta VALUES ('version','{ver}');
INSERT INTO users VALUES (1,'legacy','x','2026-01-01',NULL,NULL,NULL,1);
INSERT INTO bots(id,user_id,name,created_at,allowed_tools) VALUES (1,1,'Old','2026-01-01','{tools}');
CREATE TABLE mcp_servers (
  id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL, slug TEXT NOT NULL, source TEXT NOT NULL,
  catalog_id TEXT, name TEXT NOT NULL, transport TEXT NOT NULL, url TEXT, trust TEXT NOT NULL,
  auth_type TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'needs_auth', account_label TEXT,
  granted_scopes TEXT, discover_json TEXT, last_synced_at TEXT, last_error TEXT,
  consent_at TEXT, sync_status TEXT NOT NULL DEFAULT 'pending',
  circuit_failures INTEGER NOT NULL DEFAULT 0, circuit_open_until TEXT,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL, UNIQUE(user_id, slug));
CREATE TABLE mcp_tools (
  id INTEGER PRIMARY KEY, server_id INTEGER NOT NULL, user_id INTEGER NOT NULL, mcp_name TEXT NOT NULL,
  full_name TEXT NOT NULL, title TEXT, description TEXT NOT NULL, input_schema TEXT NOT NULL,
  output_schema TEXT, annotations TEXT, def_hash TEXT NOT NULL, accepted_hash TEXT,
  risk TEXT NOT NULL, confirm_policy TEXT NOT NULL DEFAULT 'default', status TEXT NOT NULL DEFAULT 'active',
  first_seen_at TEXT NOT NULL, last_seen_at TEXT NOT NULL);
"""


def v9(ver, learn_sql, aws_sql, tools="[]", tool_sql=""):
    return BASE_V8.format(ver=ver, tools=tools) + learn_sql + aws_sql + tool_sql


LEARN_UNUSED = """
INSERT INTO mcp_servers(id,user_id,slug,source,catalog_id,name,transport,url,trust,auth_type,status,sync_status,created_at,updated_at)
 VALUES (3,1,'learn','catalog','microsoft_learn','Microsoft Learn','streamable_http','http://example.test/mcp','verified','none','needs_auth','pending','2026-10-01T00:00:00+00:00','2026-10-01T00:00:00+00:00');
"""
LEARN_CONSENT = """
INSERT INTO mcp_servers(id,user_id,slug,source,catalog_id,name,transport,url,trust,auth_type,status,consent_at,last_synced_at,sync_status,created_at,updated_at)
 VALUES (3,1,'learn','catalog','microsoft_learn','Microsoft Learn','streamable_http','http://example.test/mcp','verified','none','connected','2026-10-02T00:00:00+00:00','2026-10-03T01:00:00+00:00','ok','2026-10-01T00:00:00+00:00','2026-10-03T01:00:00+00:00');
"""
LEARN_DISABLED_USED = """
INSERT INTO mcp_servers(id,user_id,slug,source,catalog_id,name,transport,url,trust,auth_type,status,consent_at,sync_status,created_at,updated_at)
 VALUES (3,1,'learn','catalog','microsoft_learn','Microsoft Learn','streamable_http','http://example.test/mcp','verified','none','disabled','2026-10-02T00:00:00+00:00','pending','2026-10-01T00:00:00+00:00','2026-10-02T00:00:00+00:00');
"""
AWS_UNUSED = """
INSERT INTO mcp_servers(id,user_id,slug,source,catalog_id,name,transport,trust,auth_type,status,sync_status,created_at,updated_at)
 VALUES (4,1,'aws','catalog','aws_knowledge','AWS Knowledge','streamable_http','verified','none','disabled','pending','2026-10-01T00:00:00+00:00','2026-10-01T00:00:00+00:00');
"""
TOOL_SQL = """
INSERT INTO mcp_tools(id,server_id,user_id,mcp_name,full_name,description,input_schema,def_hash,risk,status,first_seen_at,last_seen_at)
 VALUES (9,3,1,'microsoft_docs_search','mcp__learn__microsoft_docs_search','d','{}','abc','read','active','2026-10-03T01:00:00+00:00','2026-10-03T01:00:00+00:00');
"""

fresh = migrate("empty", "1", "CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL); INSERT INTO schema_meta VALUES ('version','1');")
# empty script still needs a users table? init_db CREATE IF NOT EXISTS from SCHEMA. version 1 with only schema_meta is enough
# if users missing, SCHEMA creates it. Good.

check("PLG-01 empty database reaches v12 twice",
      fresh["ver"] == "12" and fresh["has_plugins"] and fresh["n1"] == fresh["n2"] == 0 and fresh["tomb"] == 0,
      str(fresh))

v8 = migrate("v8", "8", v9("8", LEARN_UNUSED, AWS_UNUSED))
check("PLG-01 v8 backfills plugin_id and does not add rows on the second start",
      v8["ver"] == "12" and v8["has_plugins"] and v8["has_plugin_id"]
      and v8["learn"] and v8["learn"][0] == "microsoft_learn" and v8["n1"] == v8["n2"],
      str(v8))

used = migrate("used", "9", v9("9", LEARN_CONSENT, AWS_UNUSED, tools='["get_weather","mcp__learn__microsoft_docs_search"]', tool_sql=TOOL_SQL))
check("PLG-02 consented synced Learn stays installed without touching consent or allowlist",
      used["ver"] == "12"
      and ["1", "microsoft_learn", "installed"] in [list(map(str, p)) for p in used["plugins"]]
      and used["learn"][1] == "2026-10-02T00:00:00+00:00"
      and used["bots"] == ['["get_weather","mcp__learn__microsoft_docs_search"]']
      and all(p[1] != "aws_knowledge" or p[2] != "installed" for p in used["plugins"]),
      str(used))

unused = migrate("unused", "9", v9("9", LEARN_UNUSED, AWS_UNUSED))
installed_ids = {p[1] for p in unused["plugins"] if p[2] == "installed"}
check("PLG-02b unused Learn and AWS stay not installed and are not tombstoned",
      "microsoft_learn" not in installed_ids and "aws_knowledge" not in installed_ids
      and unused["tomb"] == 0 and unused["n1"] == unused["n2"],
      str(unused))

on_bot = migrate("onbot", "9", v9(
    "9", LEARN_UNUSED, AWS_UNUSED, tools='["mcp__aws__aws___list_regions"]'))
check("PLG-02c used on a Bot migrates installed; unused sibling does not",
      any(p[1] == "aws_knowledge" and p[2] == "installed" for p in on_bot["plugins"])
      and not any(p[1] == "microsoft_learn" for p in on_bot["plugins"])
      and on_bot["tomb"] == 0,
      str(on_bot))

disabled_used = migrate("disabled", "9", v9("9", LEARN_DISABLED_USED, ""))
check("PLG-02c consented but disabled Learn migrates installed",
      any(p[1] == "microsoft_learn" and p[2] == "installed" for p in disabled_used["plugins"])
      and disabled_used["tomb"] == 0,
      str(disabled_used))

# ---------- API ----------
mock = MockMCP(list_delay=1.2, call_delay=0.0)
os.environ["VERABOT_MCP_LEARN_URL"] = mock.url
os.environ["VERABOT_MCP_AWS_URL"] = mock.url
try:
    from fastapi.testclient import TestClient
    from verabot import db
    from verabot.main import app
    from verabot.core.config import plugin_default_installed
    db.init_db()
    check("PLG-04 default_installed is empty", plugin_default_installed() == set(), str(plugin_default_installed()))
    cli = TestClient(app)
    token = cli.post("/api/auth/register", json={"username": "plug", "password": "pw123456"}).json()["token"]
    H = {"Authorization": "Bearer " + token}
    t0 = time.perf_counter()
    listed = cli.get("/api/plugins", headers=H)
    elapsed = time.perf_counter() - t0
    body = listed.json()
    ids = [p["plugin_id"] for p in body["plugins"]]
    check("PLG-04 new user installed list has no external plugin and does not touch the network",
          listed.status_code == 200 and elapsed < 0.7 and "microsoft_learn" not in ids and "aws_knowledge" not in ids
          and mock.lists == 0 and "cache-control" in {k.lower() for k in listed.headers}
          and listed.headers.get("cache-control") == "no-store",
          f"elapsed={elapsed:.3f} ids={ids} lists={mock.lists} headers={listed.headers.get('cache-control')}")
    check("PLG-11 builtins are listed and not removable",
          {"builtin_weather", "builtin_reminder"} <= set(ids)
          and all(p["kind"] == "builtin" and p["removable"] is False and p["state"] == "ready"
                  for p in body["plugins"] if p["kind"] == "builtin"),
          str(ids))
    for path, method in (
        ("/api/plugins/builtin_weather", "DELETE"),
        ("/api/plugins/builtin_weather/consent", "POST"),
        ("/api/plugins/builtin_weather", "PATCH"),
    ):
        resp = cli.request(method, path, headers=H, json={"granted": True, "enabled": False})
        check(f"PLG-11 {method} {path} is 422", resp.status_code == 422, resp.text[:180])

    mock.list_delay = 0
    first = cli.post("/api/plugins/aws_knowledge/install", headers=H)
    again = cli.post("/api/plugins/aws_knowledge/install", headers=H)
    servers = cli.get("/api/mcp/servers", headers=H).json()["servers"]
    check("PLG-05 install returns 201 then 409 and reuses nothing new on the second try",
          first.status_code == 201 and first.json()["plugin_id"] == "aws_knowledge"
          and first.json()["consent_at"] is None and first.json()["installed"] is True
          and again.status_code == 409
          and len([s for s in servers if s["slug"] == "aws"]) == 1,
          f"first={first.status_code} again={again.status_code} {first.text[:240]}")

    # 停掉 AWS，改测 Learn 的同意 / 调用 / 卸载。AWS 行留着会被卸载测试干扰，先卸掉。
    cli.delete("/api/plugins/aws_knowledge", headers=H)
    mock.calls = 0
    inst = cli.post("/api/plugins/microsoft_learn/install", headers=H)
    deadline = time.time() + 8
    learn = inst.json()
    while time.time() < deadline and learn.get("state") == "syncing":
        time.sleep(0.05)
        learn = cli.get("/api/plugins/microsoft_learn", headers=H).json()
    check("PLG-10 syncing then needs_consent",
          inst.status_code == 201 and learn["state"] == "needs_consent" and learn["sync_status"] == "ok",
          str({k: learn.get(k) for k in ("state", "sync_status", "enabled")}))

    me = cli.get("/api/me", headers=H).json()
    bot = cli.post("/api/bots", json={"name": "Vera"}, headers=H).json()
    tools = cli.get("/api/plugins/microsoft_learn/tools", headers=H).json()["tools"]
    full = next(t["full_name"] for t in tools if t["mcp_name"] == "microsoft_docs_search")
    cli.patch(f"/api/bots/{bot['id']}", json={"allowed_tools": [full]}, headers=H)

    from verabot.agents.tool_router import dispatch
    from verabot.tools.registry import ToolContext, TurnState
    from verabot import db
    fresh_bot = db.get_bot(me["id"], bot["id"])
    ctx = ToolContext(user_id=me["id"], bot=fresh_bot, depth=0, turn=TurnState())

    def run(coro):
        import asyncio
        return asyncio.run(coro)

    refused = run(dispatch(ctx, full, '{"query":"q"}', call_id="p_no"))
    granted = cli.post("/api/plugins/microsoft_learn/consent", json={"granted": True}, headers=H)
    con = sqlite3.connect(DB)
    audits = [json.loads(r[0]) for r in con.execute(
        "SELECT detail FROM audit_log WHERE kind='mcp_consent_granted' AND user_id=?", (me["id"],)
    ).fetchall()]
    con.close()
    called = run(dispatch(ToolContext(user_id=me["id"], bot=fresh_bot, depth=0, turn=TurnState()), full, '{"query":"q"}', call_id="p_ok"))
    revoked = cli.post("/api/plugins/microsoft_learn/consent", json={"granted": False}, headers=H)
    after = run(dispatch(ToolContext(user_id=me["id"], bot=fresh_bot, depth=0, turn=TurnState()), full, "{}", call_id="p_rev"))
    check("PLG-06 consent writes plugin_id and revoke blocks the call",
          refused.get("code") == "mcp_consent_required"
          and granted.status_code == 200 and granted.json()["consent_at"]
          and any(a.get("plugin_id") == "microsoft_learn" for a in audits)
          and called.get("code") == "ok"
          and revoked.json()["consent_at"] is None
          and after.get("code") == "mcp_consent_required",
          f"refused={refused.get('code')} called={called.get('code')} audits={audits[:1]}")
    cli.post("/api/plugins/microsoft_learn/consent", json={"granted": True}, headers=H)

    # state order: disabled wins over an open circuit
    server_id = learn["servers"][0]["id"]
    con = sqlite3.connect(DB)
    future = "2099-01-01T00:00:00+00:00"
    con.execute("UPDATE mcp_servers SET status='disabled', circuit_open_until=?, circuit_failures=9, sync_status='error' WHERE id=?",
                (future, server_id))
    con.commit(); con.close()
    disabled = cli.get("/api/plugins/microsoft_learn", headers=H).json()
    con = sqlite3.connect(DB)
    con.execute("UPDATE mcp_servers SET status='connected', sync_status='ok' WHERE id=?", (server_id,))
    con.commit(); con.close()
    opened = cli.get("/api/plugins/microsoft_learn", headers=H).json()
    con = sqlite3.connect(DB)
    con.execute("UPDATE mcp_servers SET circuit_open_until=NULL, circuit_failures=0, sync_status='syncing', status='connected' WHERE id=?", (server_id,))
    con.commit(); con.close()
    syncing = cli.get("/api/plugins/microsoft_learn", headers=H).json()
    con = sqlite3.connect(DB)
    con.execute("UPDATE mcp_servers SET sync_status='error', status='error', consent_at=NULL WHERE id=?", (server_id,))
    con.commit(); con.close()
    errored = cli.get("/api/plugins/microsoft_learn", headers=H).json()
    con = sqlite3.connect(DB)
    con.execute("UPDATE mcp_servers SET sync_status='ok', status='connected', consent_at=NULL, last_error=NULL WHERE id=?", (server_id,))
    con.commit(); con.close()
    needs = cli.get("/api/plugins/microsoft_learn", headers=H).json()
    con = sqlite3.connect(DB)
    con.execute("UPDATE mcp_servers SET consent_at='2026-10-03T00:00:00+00:00' WHERE id=?", (server_id,))
    con.commit(); con.close()
    ready = cli.get("/api/plugins/microsoft_learn", headers=H).json()
    check("PLG-10 state order disabled, circuit_open, syncing, error, needs_consent, ready",
          [disabled["state"], opened["state"], syncing["state"], errored["state"], needs["state"], ready["state"]]
          == ["disabled", "circuit_open", "syncing", "error", "needs_consent", "ready"],
          str([disabled["state"], opened["state"], syncing["state"], errored["state"], needs["state"], ready["state"]]))

    synced = cli.post("/api/plugins/microsoft_learn/sync", headers=H)
    turned = cli.patch("/api/plugins/microsoft_learn", json={"enabled": False}, headers=H)
    blocked = cli.post("/api/plugins/microsoft_learn/sync", headers=H)
    from verabot.agents.tool_router import schemas_for
    bot_off = db.get_bot(me["id"], bot["id"])
    names = [s["function"]["name"] for s in schemas_for(bot_off, 0, False, me["id"])]
    denied = run(dispatch(ToolContext(user_id=me["id"], bot=bot_off, depth=0, turn=TurnState()), full, "{}", call_id="p_off"))
    check("PLG-09 disable hides the tool and sync is 409",
          synced.status_code == 200 and "plugin" in synced.json()
          and turned.status_code == 200 and turned.json()["state"] == "disabled"
          and blocked.status_code == 409 and full not in names and denied.get("code") == "not_connected",
          f"sync={synced.status_code} off={turned.json().get('state')} block={blocked.status_code} code={denied.get('code')}")
    cli.patch("/api/plugins/microsoft_learn", json={"enabled": True}, headers=H)
    # 重新启用会后台同步；等它结束再卸载，避免和 PLG-14 抢同一行
    deadline = time.time() + 8
    while time.time() < deadline:
        cur = cli.get("/api/plugins/microsoft_learn", headers=H).json()
        if cur["state"] != "syncing":
            break
        time.sleep(0.05)

    cli.post("/api/plugins/microsoft_learn/consent", json={"granted": True}, headers=H)
    removed = cli.delete("/api/plugins/microsoft_learn", headers=H)
    plugins_after = [p["plugin_id"] for p in cli.get("/api/plugins", headers=H).json()["plugins"]]
    servers_after = cli.get("/api/mcp/servers", headers=H).json()["servers"]
    allow = db.get_bot(me["id"], bot["id"])["allowed_tools"]
    con = sqlite3.connect(DB)
    tomb = con.execute(
        "SELECT status FROM user_plugins WHERE user_id=? AND plugin_id='microsoft_learn'", (me["id"],)
    ).fetchone()[0]
    tool_left = con.execute("SELECT COUNT(*) FROM mcp_tools WHERE user_id=? AND full_name=?", (me["id"], full)).fetchone()[0]
    audit_un = con.execute(
        "SELECT detail FROM audit_log WHERE user_id=? AND kind='plugin_uninstalled'", (me["id"],)
    ).fetchall()
    con.close()
    check("PLG-07 uninstall strips bots, drops the cache, and does not come back",
          removed.status_code == 200 and removed.json()["ok"] is True and removed.json()["affected_bots"] >= 1
          and "microsoft_learn" not in plugins_after and servers_after == []
          and full not in allow and tomb == "uninstalled" and tool_left == 0
          and any("microsoft_learn" in r[0] for r in audit_un),
          removed.text[:240])

    old_audits = sqlite3.connect(DB).execute(
        "SELECT COUNT(*) FROM audit_log WHERE user_id=? AND kind='plugin_uninstalled'", (me["id"],)
    ).fetchone()[0]
    reinstall = cli.post("/api/plugins/microsoft_learn/install", headers=H)
    re_id = reinstall.json()["servers"][0]["id"]
    check("PLG-08 reinstall is 201 with empty consent and keeps the old audit",
          reinstall.status_code == 201 and reinstall.json()["consent_at"] is None
          and re_id != server_id
          and sqlite3.connect(DB).execute(
              "SELECT COUNT(*) FROM audit_log WHERE user_id=? AND kind='plugin_uninstalled'", (me["id"],)
          ).fetchone()[0] == old_audits,
          reinstall.text[:240])

    # 等同步完再做进行中调用
    deadline = time.time() + 8
    while time.time() < deadline:
        cur = cli.get("/api/plugins/microsoft_learn", headers=H).json()
        if cur.get("sync_status") == "ok":
            break
        time.sleep(0.05)
    cli.post("/api/plugins/microsoft_learn/consent", json={"granted": True}, headers=H)
    cli.patch(f"/api/bots/{bot['id']}", json={"allowed_tools": [full]}, headers=H)
    fresh_bot = db.get_bot(me["id"], bot["id"])
    server_row_id = cur["servers"][0]["id"]

    mock.call_delay = 1.5
    mock.calls = 0
    box = {}

    def _in_flight():
        import asyncio
        box["ctx"] = ToolContext(user_id=me["id"], bot=fresh_bot, depth=0, turn=TurnState())
        try:
            box["result"] = asyncio.run(dispatch(box["ctx"], full, '{"query":"slow"}', call_id="p_slow"))
        except Exception as exc:
            box["error"] = repr(exc)

    worker = threading.Thread(target=_in_flight)
    worker.start()
    time.sleep(0.3)
    t_un = time.perf_counter()
    gone = cli.delete("/api/plugins/microsoft_learn", headers=H)
    uninstall_s = time.perf_counter() - t_un
    worker.join(timeout=5)
    from verabot.services.mcp.http_client import _POOL
    second = run(dispatch(ToolContext(user_id=me["id"], bot=fresh_bot, depth=0, turn=TurnState()), full, "{}", call_id="p_again"))
    con = sqlite3.connect(DB)
    slow_audit = [json.loads(r[0]) for r in con.execute(
        "SELECT detail FROM audit_log WHERE user_id=? AND kind='mcp_tool_call'", (me["id"],)
    ).fetchall()]
    con.close()
    slow = next((a for a in slow_audit if a.get("call_id") == "p_slow"), {})
    check("PLG-14 in-flight call is cancelled without retry, taint, or a pooled session",
          gone.status_code == 200 and uninstall_s < 0.5 and "error" not in box
          and box.get("result", {}).get("code") == "plugin_uninstalled"
          and mock.calls == 1
          and box["ctx"].turn.untrusted_tainted is False
          and slow.get("status") == "cancelled" and slow.get("error_class") == "plugin_uninstalled"
          and second.get("code") == "plugin_uninstalled"
          and (me["id"], server_row_id) not in _POOL,
          f"uninstall={uninstall_s:.3f}s result={box.get('result')} err={box.get('error')} calls={mock.calls} second={second.get('code')} audit={slow} pool={list(_POOL)}")

    mock.call_delay = 0
    mock.list_delay = 1.5
    mock.lists = 0
    import logging
    caught = []

    class _Grab(logging.Handler):
        def emit(self, record):
            caught.append(record)

    grab = _Grab()
    logging.getLogger("verabot.mcp").addHandler(grab)
    try:
        inst2 = cli.post("/api/plugins/microsoft_learn/install", headers=H)
        gone2 = cli.delete("/api/plugins/microsoft_learn", headers=H)
        time.sleep(2.0)
    finally:
        logging.getLogger("verabot.mcp").removeHandler(grab)
    con = sqlite3.connect(DB)
    left_tools = con.execute(
        "SELECT COUNT(*) FROM mcp_tools WHERE user_id=? AND full_name LIKE 'mcp__learn__%'", (me["id"],)
    ).fetchone()[0]
    status = con.execute(
        "SELECT status FROM user_plugins WHERE user_id=? AND plugin_id='microsoft_learn'", (me["id"],)
    ).fetchone()[0]
    con.close()
    leaked = [r for r in caught if r.levelno >= logging.ERROR and ("FOREIGN KEY" in r.getMessage() or "IntegrityError" in r.getMessage())]
    check("PLG-15 uninstall during sync leaves no tools and no foreign-key error",
          inst2.status_code == 201 and gone2.status_code == 200 and left_tools == 0 and status == "uninstalled"
          and not leaked,
          f"tools={left_tools} status={status} errors={[r.getMessage() for r in leaked]}")

    other = cli.post("/api/auth/register", json={"username": "plugb", "password": "pw123456"}).json()["token"]
    H2 = {"Authorization": "Bearer " + other}
    foreign = cli.get("/api/plugins/microsoft_learn", headers=H2)
    foreign_tools = cli.get("/api/plugins/microsoft_learn/tools", headers=H2)
    foreign_consent = cli.post("/api/plugins/microsoft_learn/consent", json={"granted": True}, headers=H2)
    foreign_del = cli.delete("/api/plugins/microsoft_learn", headers=H2)
    cat = cli.get("/api/plugins/catalog", headers=H)
    one = cli.get("/api/plugins/builtin_weather", headers=H)
    tool_list = cli.get("/api/plugins/builtin_weather/tools", headers=H)
    check("PLG-12 other user cannot see or change this install, and plugin GETs are no-store",
          foreign.status_code == 404 and foreign_tools.status_code == 404
          and foreign_consent.status_code == 404 and foreign_del.status_code == 404
          and cat.headers.get("cache-control") == "no-store"
          and one.headers.get("cache-control") == "no-store"
          and tool_list.headers.get("cache-control") == "no-store"
          and listed.headers.get("cache-control") == "no-store",
          f"{foreign.status_code} {foreign_tools.status_code} {foreign_consent.status_code} {foreign_del.status_code}")

    # 装上并同步，检查 /api/tools
    mock.list_delay = 0
    cli.post("/api/plugins/microsoft_learn/install", headers=H)
    deadline = time.time() + 8
    while time.time() < deadline:
        if cli.get("/api/plugins/microsoft_learn", headers=H).json().get("sync_status") == "ok":
            break
        time.sleep(0.05)
    cli.post("/api/plugins/microsoft_learn/consent", json={"granted": True}, headers=H)
    # consent 之后工具才会出现在 /api/tools（connected + consent）
    # 同步已完成但 consent 后 status 仍 connected。connected_tool_rows 需要 consent。
    tools_body = cli.get("/api/tools", headers=H).json()["tools"]
    weather = next(t for t in tools_body if t["name"] == "get_weather")
    ask = next(t for t in tools_body if t["name"] == "ask_bot")
    mcp_tool = next((t for t in tools_body if t["name"] == full), None)
    check("PLG-13 tools carry plugin_id and keep the old fields",
          weather["plugin_id"] == "builtin_weather" and weather["source"] == "builtin"
          and ask["plugin_id"] is None
          and mcp_tool and mcp_tool["plugin_id"] == "microsoft_learn" and mcp_tool["source"] == "mcp"
          and mcp_tool["server_id"] and "risk" in mcp_tool,
          str({t["name"]: t.get("plugin_id") for t in tools_body}))

    core = (IOS / "VeraBotCore/Plugin.swift").read_text()
    models = (IOS / "VeraBotCore/Models.swift").read_text()
    mcp_swift = (IOS / "VeraBotCore/MCP.swift").read_text()
    plugin_json = cli.get("/api/plugins/microsoft_learn", headers=H).json()
    sync_json = cli.post("/api/plugins/microsoft_learn/sync", headers=H).json()
    tools_json = cli.get("/api/plugins/microsoft_learn/tools", headers=H).json()
    check("PLG-CONTRACT Plugin and ToolInfo keys are a subset of the JSON",
          _keys(core, "Plugin") <= set(plugin_json)
          and _keys(core, "PluginSyncResult") <= set(sync_json)
          and _keys(core, "PluginToolsResponse") <= set(tools_json)
          and _keys(mcp_swift, "MCPTool") <= set(tools_json["tools"][0])
          and _keys(models, "ToolInfo") <= set(weather)
          and _keys(models, "ToolInfo") <= set(mcp_tool),
          f"plugin missing {_keys(core,'Plugin')-set(plugin_json)} "
          f"sync missing {_keys(core,'PluginSyncResult')-set(sync_json)} "
          f"tool missing {_keys(mcp_swift,'MCPTool')-set(tools_json['tools'][0])} "
          f"info missing {_keys(models,'ToolInfo')-set(mcp_tool)}")
finally:
    mock.stop()

print(f"\nPlugin tests failed: {len(FAILS)}")
sys.exit(1 if FAILS else 0)
