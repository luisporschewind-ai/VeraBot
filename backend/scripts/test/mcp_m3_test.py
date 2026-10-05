#!/usr/bin/env python3
"""MCP M3：pending_actions HITL（MCP-10~13、pending 上限、跨服务警告、工具调用记录）。

假 MCP 服务器带一个写工具 delete_item；不访问外网。
"""
import asyncio
import json
import os
import sqlite3
import sys
import tempfile
import threading
import time
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TMP = tempfile.mkdtemp(prefix="vb_mcp_m3_")
DB = str(Path(TMP) / "t.db")
os.environ["VERABOT_DB"] = DB
os.environ["VERABOT_DATA_DIR"] = TMP
os.environ.setdefault("DEEPSEEK_API_KEY", "test-not-used")
os.environ["VERABOT_MCP_AWS_ENABLED"] = "0"
os.environ["VERABOT_ACTION_TTL_MIN"] = "15"
os.environ["VERABOT_MCP_PENDING_PER_TURN"] = "2"
sys.path.insert(0, str(ROOT))

from fastapi.testclient import TestClient

from verabot import db
from verabot.main import app

FAILS = []
IOS = ROOT.parent / "frontend/ios/Packages/VeraBotKit/Sources"


def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else " " + detail))
    if not ok:
        FAILS.append(name)


def asyncio_run(coro):
    return asyncio.get_event_loop().run_until_complete(coro) if False else asyncio.run(coro)


class MockMCP(ThreadingHTTPServer):
    allow_reuse_address = True

    def __init__(self, tools=None):
        self.tools = tools or []
        self.requests = []
        self.call_count = 0
        self.session_id = "m3-sess"
        self.server_protocol = "2025-03-26"
        self.delay = 0
        self.expire_once = False
        self.fail_calls = 0
        self.slow_calls = 0
        self.call_delay = 0
        self.is_error_remaining = 0
        self.http_400_remaining = 0
        super().__init__(("127.0.0.1", 0), _Handler)
        self.thread = threading.Thread(target=self.serve_forever, daemon=True)
        self.thread.start()

    @property
    def url(self):
        return f"http://127.0.0.1:{self.server_address[1]}/mcp"

    def stop(self):
        self.shutdown()
        self.server_close()

    def tool_calls(self):
        return [r for r in self.requests if (r.get("body") or {}).get("method") == "tools/call"]


class _Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""
        try:
            body = json.loads(raw.decode() or "{}")
        except json.JSONDecodeError:
            body = {}
        srv = self.server
        srv.requests.append({"body": body, "session": self.headers.get("Mcp-Session-Id")})
        method = body.get("method")
        if method == "notifications/initialized":
            self._reply(202, None)
            return
        if method == "initialize":
            self._reply(200, {"jsonrpc": "2.0", "id": body.get("id"), "result": {
                "protocolVersion": srv.server_protocol,
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "mock-m3", "version": "0"},
            }})
            return
        if method == "tools/list":
            self._reply(200, {"jsonrpc": "2.0", "id": body.get("id"), "result": {"tools": srv.tools}})
            return
        if method == "tools/call":
            srv.call_count += 1
            name = (body.get("params") or {}).get("name")
            args = (body.get("params") or {}).get("arguments") or {}
            text = f"deleted:{args.get('id')}" if name == "delete_item" else f"ok:{name}"
            self._reply(200, {"jsonrpc": "2.0", "id": body.get("id"), "result": {
                "content": [{"type": "text", "text": text}],
            }})
            return
        self._reply(200, {"jsonrpc": "2.0", "id": body.get("id"), "result": {}})

    def _reply(self, code, payload, send_session=True):
        body = b"" if payload is None else json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        if send_session and self.server.session_id:
            self.send_header("Mcp-Session-Id", self.server.session_id)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)


WRITE_TOOLS = [
    {
        "name": "search_docs",
        "description": "search",
        "inputSchema": {"type": "object", "properties": {"q": {"type": "string"}}},
        "annotations": {"readOnlyHint": True, "destructiveHint": False, "openWorldHint": False},
    },
    {
        "name": "delete_item",
        "description": "delete something",
        "inputSchema": {
            "type": "object",
            "properties": {"id": {"type": "string"}},
            "required": ["id"],
        },
        "annotations": {"readOnlyHint": False, "destructiveHint": True, "openWorldHint": False},
    },
    {
        "name": "send_note",
        "description": "send a note",
        "inputSchema": {"type": "object", "properties": {"text": {"type": "string"}}},
        "annotations": {"readOnlyHint": False, "destructiveHint": False, "openWorldHint": True},
    },
]

mock = MockMCP(tools=WRITE_TOOLS)
os.environ["VERABOT_MCP_LEARN_URL"] = mock.url
db.init_db()
cli = TestClient(app)

reg = cli.post("/api/auth/register", json={"username": "m3user", "password": "verabot2026"})
check("M3-setup register", reg.status_code in (200, 201), reg.text[:200])
token = reg.json()["token"]
H = {"Authorization": f"Bearer {token}"}
me = cli.get("/api/me", headers=H).json()

# 安装 Learn（指向假服务器）并同意、同步
installed = cli.post("/api/plugins/microsoft_learn/install", headers=H)
check("M3-setup install learn", installed.status_code in (200, 201), installed.text[:200])
# 等同步
deadline = time.time() + 8
server = None
while time.time() < deadline:
    servers = cli.get("/api/mcp/servers", headers=H).json()["servers"]
    server = next((s for s in servers if s["slug"] == "learn"), None)
    if server and server.get("sync_status") in ("ok", "error") and server.get("status") == "connected":
        break
    time.sleep(0.05)
check("M3-setup synced", server is not None and server["status"] == "connected", str(server)[:200])
cli.post(f"/api/mcp/servers/{server['id']}/consent", json={"granted": True}, headers=H)
tools = {t["mcp_name"]: t for t in cli.get(f"/api/mcp/servers/{server['id']}/tools", headers=H).json()["tools"]}
check("M3-setup tools mapped",
      "delete_item" in tools and tools["delete_item"]["risk"] in ("destructive", "send", "write")
      and tools["delete_item"]["requires_confirmation"] is True
      and tools["search_docs"]["risk"] == "read",
      str({k: (tools[k]["risk"], tools[k]["requires_confirmation"]) for k in tools}))

bot = cli.post("/api/bots", json={"name": "M3Bot"}, headers=H).json()
full_del = tools["delete_item"]["full_name"]
full_read = tools["search_docs"]["full_name"]
full_send = tools["send_note"]["full_name"]
cli.patch(f"/api/bots/{bot['id']}", json={"allowed_tools": [full_del, full_read, full_send, "get_weather"]}, headers=H)

from verabot.agents.tool_router import dispatch
from verabot.tools.registry import ToolContext, TurnState

fresh = db.get_bot(me["id"], bot["id"])
calls_before = mock.call_count
ctx = ToolContext(user_id=me["id"], bot=fresh, depth=0, turn=TurnState())
pending = asyncio_run(dispatch(ctx, full_del, '{"id":"item-42"}', call_id="c_pend"))
check("MCP-10 needs confirmation creates pending, no remote call",
      pending.get("status") == "pending_confirmation"
      and isinstance(pending.get("action_id"), int)
      and pending.get("arguments", {}).get("id") == "item-42"
      and mock.call_count == calls_before
      and ctx.turn.pending_created == 1
      and ctx.turn.mcp_calls == 0,
      str(pending)[:300] + f" calls={mock.call_count}")

action_id = pending["action_id"]
# 他人 → 404
other = cli.post("/api/auth/register", json={"username": "m3other", "password": "verabot2026"}).json()
oth = {"Authorization": f"Bearer {other['token']}"}
r404 = cli.post(f"/api/pending-actions/{action_id}/confirm", headers=oth)
check("MCP-11 other user 404", r404.status_code == 404, r404.text[:160])

# confirm 执行冻结参数且只一次
r_ok = cli.post(f"/api/pending-actions/{action_id}/confirm", headers=H)
call_bodies = [json.dumps(r.get("body"), ensure_ascii=False) for r in mock.tool_calls()]
check("MCP-11 confirm executes frozen args once",
      r_ok.status_code == 200 and r_ok.json().get("status") == "done"
      and mock.call_count == calls_before + 1
      and any("item-42" in b for b in call_bodies),
      r_ok.text[:300] + f" calls={mock.call_count} bodies={call_bodies[-1] if call_bodies else None}")

r_dup = cli.post(f"/api/pending-actions/{action_id}/confirm", headers=H)
check("MCP-11 duplicate confirm 409",
      r_dup.status_code == 409, r_dup.text[:200])

# 过期 → 410
ctx2 = ToolContext(user_id=me["id"], bot=fresh, depth=0, turn=TurnState())
p2 = asyncio_run(dispatch(ctx2, full_del, '{"id":"x"}', call_id="c_exp"))
aid2 = p2["action_id"]
past = (datetime.now(timezone.utc) - timedelta(minutes=1)).isoformat(timespec="seconds")
with db.tx() as c:
    c.execute("UPDATE pending_actions SET expires_at=? WHERE id=?", (past, aid2))
r410 = cli.post(f"/api/pending-actions/{aid2}/confirm", headers=H)
check("MCP-11 expired 410", r410.status_code == 410, r410.text[:200])

# MCP-12：confirm 前工具定义变更
ctx3 = ToolContext(user_id=me["id"], bot=fresh, depth=0, turn=TurnState())
p3 = asyncio_run(dispatch(ctx3, full_del, '{"id":"chg"}', call_id="c_chg"))
aid3 = p3["action_id"]
with db.tx() as c:
    c.execute("UPDATE mcp_tools SET status='changed' WHERE full_name=? AND user_id=?",
              (full_del, me["id"]))
r_chg = cli.post(f"/api/pending-actions/{aid3}/confirm", headers=H)
check("MCP-12 tool_changed before confirm → 409, no call",
      r_chg.status_code == 409 and "变更" in r_chg.text
      and mock.call_count == calls_before + 1,
      r_chg.text[:200])
# 恢复 active
with db.tx() as c:
    c.execute("UPDATE mcp_tools SET status='active' WHERE full_name=? AND user_id=?",
              (full_del, me["id"]))

# 服务器断开
ctx4 = ToolContext(user_id=me["id"], bot=fresh, depth=0, turn=TurnState())
p4 = asyncio_run(dispatch(ctx4, full_del, '{"id":"disc"}', call_id="c_disc"))
aid4 = p4["action_id"]
cli.patch(f"/api/mcp/servers/{server['id']}", json={"enabled": False}, headers=H)
r_disc = cli.post(f"/api/pending-actions/{aid4}/confirm", headers=H)
check("MCP-12 server disconnected → 409",
      r_disc.status_code == 409 and mock.call_count == calls_before + 1,
      r_disc.text[:200])
cli.patch(f"/api/mcp/servers/{server['id']}", json={"enabled": True}, headers=H)
# 重新同意（停用可能清状态）
time.sleep(0.2)
cli.post(f"/api/mcp/servers/{server['id']}/consent", json={"granted": True}, headers=H)

# MCP-13：发送类不能设自动执行
send_id = tools["send_note"]["id"]
r_auto = cli.patch(f"/api/mcp/tools/{send_id}", json={"confirm_policy": "never"}, headers=H)
check("MCP-13 send tool cannot auto-execute (422)",
      r_auto.status_code == 422, r_auto.text[:200])
r_bad = cli.patch(f"/api/mcp/tools/{send_id}", json={"confirm_policy": "auto"}, headers=H)
check("MCP-13 auto policy 422", r_bad.status_code == 422, r_bad.text[:160])
r_ok_pol = cli.patch(f"/api/mcp/tools/{send_id}", json={"confirm_policy": "always"}, headers=H)
check("MCP-13 always policy accepted",
      r_ok_pol.status_code == 200 and r_ok_pol.json().get("requires_confirmation") is True,
      r_ok_pol.text[:200])

# 取消
ctx5 = ToolContext(user_id=me["id"], bot=fresh, depth=0, turn=TurnState())
p5 = asyncio_run(dispatch(ctx5, full_del, '{"id":"cancel-me"}', call_id="c_can"))
r_can = cli.post(f"/api/pending-actions/{p5['action_id']}/cancel", headers=H)
check("M3-cancel",
      r_can.status_code == 200 and r_can.json().get("status") == "cancelled"
      and mock.call_count == calls_before + 1,
      r_can.text[:200])

# pending 上限
os.environ["VERABOT_MCP_PENDING_PER_TURN"] = "2"
ctx6 = ToolContext(user_id=me["id"], bot=fresh, depth=0, turn=TurnState())
a = asyncio_run(dispatch(ctx6, full_del, '{"id":"a"}', call_id="c_a"))
b = asyncio_run(dispatch(ctx6, full_del, '{"id":"b"}', call_id="c_b"))
c_cap = asyncio_run(dispatch(ctx6, full_del, '{"id":"c"}', call_id="c_c"))
check("MCP-29 pending_cap",
      a.get("status") == "pending_confirmation" and b.get("status") == "pending_confirmation"
      and c_cap.get("code") == "pending_cap",
      str({"a": a.get("status"), "b": b.get("status"), "c": c_cap})[:240])

# 列表 + 工具调用记录
listed = cli.get("/api/pending-actions", headers=H, params={"bot_id": bot["id"]})
check("M3-list pending",
      listed.status_code == 200 and len(listed.json().get("actions", [])) >= 2,
      listed.text[:200])
calls = cli.get(f"/api/bots/{bot['id']}/tool-calls", headers=H)
check("M3-tool-calls audit",
      calls.status_code == 200 and any(x.get("kind") == "mcp_action_requested" for x in calls.json().get("tool_calls", [])),
      calls.text[:300])

# 只读仍直接调用
calls_before_read = mock.call_count
ctx_r = ToolContext(user_id=me["id"], bot=fresh, depth=0, turn=TurnState())
read_res = asyncio_run(dispatch(ctx_r, full_read, '{"q":"hi"}', call_id="c_read"))
check("M3-read still direct",
      read_res.get("code") == "ok" and mock.call_count == calls_before_read + 1
      and "untrusted_tool_result" in (read_res.get("content") or ""),
      str(read_res)[:200])

# 跨服务警告：读过 A 再向 B 写（同服不警告；直接测 policy）
from verabot.services.mcp import policy as mcp_policy
warns = mcp_policy.cross_server_warnings({"Microsoft Learn"}, "GitHub")
none = mcp_policy.cross_server_warnings({"GitHub"}, "GitHub")
check("M3-cross-server warning",
      any("Microsoft Learn" in w and "GitHub" in w for w in warns) and none == [],
      str(warns))
# 同服读后写：warnings 为空，但 turn 应记下已读服务
ctx_w = ToolContext(user_id=me["id"], bot=fresh, depth=0, turn=TurnState())
asyncio_run(dispatch(ctx_w, full_read, '{"q":"x"}', call_id="c_r2"))
pend_w = asyncio_run(dispatch(ctx_w, full_del, '{"id":"warn"}', call_id="c_w"))
check("M3-same-server no cross warning",
      pend_w.get("status") == "pending_confirmation"
      and pend_w.get("warnings") == []
      and "Microsoft Learn" in (ctx_w.turn.mcp_read_servers or set()),
      str({"warnings": pend_w.get("warnings"), "reads": list(ctx_w.turn.mcp_read_servers)}))

# 契约：iOS PendingAction / ChatEvent 键名
core = (IOS / "VeraBotCore").read_text() if False else ""
pending_swift = IOS / "VeraBotCore" / "PendingAction.swift"
api_swift = IOS / "VeraBotNetworking" / "APIClient.swift"
# 文件可能尚未写入；契约在 iOS 落地后由后续检查覆盖。这里先断言后端字段稳定。
sample = pending
needed_keys = {"action_id", "kind", "server", "tool", "label", "arguments", "risk", "warnings", "expires_at"}
check("MCP-CONTRACT confirmation payload keys",
      needed_keys <= set(sample.keys()),
      str(set(sample.keys())))

# SSE confirmation_required：用 mock LLM 太重；直接测 sse_payload
from verabot.services.actions import sse_payload
ev = sse_payload(pending)
check("M3-sse payload",
      ev.get("action_id") == pending["action_id"] and ev.get("kind") == "mcp_tool_call"
      and "arguments" in ev and "expires_at" in ev,
      str(ev)[:200])

mock.stop()
print()
if FAILS:
    print(f"FAILED {len(FAILS)}: {FAILS}")
    sys.exit(1)
print("ALL PASS")
