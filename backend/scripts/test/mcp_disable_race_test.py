#!/usr/bin/env python3
"""MCP 后台同步与「停用」的竞态（MCP-RACE-*）：确定性，进程内假 MCP 服务器，不访问外网。

假服务器的 tools/list 会阻塞在 threading.Event 上：测试线程等到同步线程确实卡在 tools/list，
再通过 API 停用服务，然后放行。另外用「旧快照」模式模拟最坏时序：同步线程之后每次读服务行都拿到停用前的快照，
相当于停用恰好落在「读完、写之前」。修复前（先读后写）这几条会失败，修复后（检查与写入同一条 SQL）必须通过。
所有用例的最终断言：服务行 status 仍是 disabled，且 sync_status 不会卡在 syncing。
"""
import json, os, sqlite3, sys, tempfile, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TMP = tempfile.mkdtemp(prefix="vb_mcprace_")
DB = str(Path(TMP) / "t.db")
os.environ["VERABOT_DB"] = DB
os.environ["VERABOT_DATA_DIR"] = TMP
os.environ.setdefault("DEEPSEEK_API_KEY", "test-not-used")
os.environ["VERABOT_MCP_AWS_ENABLED"] = "0"
os.environ["VERABOT_MCP_AWS_URL"] = "http://127.0.0.1:9/mcp"
os.environ["VERABOT_MCP_PROTOCOL_VERSION"] = "2025-06-18"
os.environ["VERABOT_MCP_RETRY_MAX"] = "0"
os.environ["VERABOT_MCP_RETRY_BACKOFF"] = "0"
os.environ["VERABOT_MCP_BREAKER_THRESHOLD"] = "5"
os.environ["VERABOT_MCP_TIMEOUT"] = "5"
sys.path.insert(0, str(ROOT))

FAILS = []
TOOLS = [{"name": "microsoft_docs_search", "description": "search", "inputSchema": {"type": "object", "properties": {}},
          "annotations": {"readOnlyHint": True}}]


def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else " " + detail))
    if not ok:
        FAILS.append(name)


class BlockingMCP(ThreadingHTTPServer):
    """tools/list 在 block=True 时先置 arrived，再等 release；之后按 list_mode 返回 ok（工具列表）或 503。"""
    allow_reuse_address = True

    def __init__(self):
        self.block = False
        self.list_mode = "ok"
        self.arrived = threading.Event()
        self.release = threading.Event()
        super().__init__(("127.0.0.1", 0), _Handler)
        threading.Thread(target=self.serve_forever, daemon=True).start()

    @property
    def url(self):
        return f"http://127.0.0.1:{self.server_address[1]}/mcp"

    def arm(self, mode: str):
        self.list_mode = mode
        self.arrived.clear()
        self.release.clear()
        self.block = True


class _Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = json.loads((self.rfile.read(length) if length else b"{}").decode() or "{}")
        srv, method = self.server, body.get("method")
        if method == "notifications/initialized":
            return self._reply(202, None)
        if method == "initialize":
            return self._reply(200, {"jsonrpc": "2.0", "id": body.get("id"), "result": {
                "protocolVersion": "2025-03-26", "capabilities": {"tools": {}},
                "serverInfo": {"name": "race", "version": "0"}}})
        if method == "tools/list":
            if srv.block:
                srv.arrived.set()
                srv.release.wait(10)
                srv.block = False
            if srv.list_mode == "503":
                return self._reply(503, None)
            return self._reply(200, {"jsonrpc": "2.0", "id": body.get("id"), "result": {"tools": TOOLS}})
        return self._reply(200, {"jsonrpc": "2.0", "id": body.get("id"),
                                 "error": {"code": -32601, "message": "unknown method"}})

    def _reply(self, status, payload):
        data = b"" if payload is None else json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Mcp-Session-Id", "race-sess")
        self.end_headers()
        if data:
            try:
                self.wfile.write(data)
            except BrokenPipeError:
                pass


mock = BlockingMCP()
os.environ["VERABOT_MCP_LEARN_URL"] = mock.url

from fastapi.testclient import TestClient  # noqa: E402
from verabot import db  # noqa: E402
from verabot.db import mcp_store  # noqa: E402
from verabot.main import app  # noqa: E402
from verabot.services.mcp import sync  # noqa: E402

db.init_db()
cli = TestClient(app)

# ---- 「旧快照」模式：同步线程读服务行时拿到停用前的快照（只影响 mcp-sync-* 线程，测试线程照常读库）----
_real_get_server = mcp_store.get_server
STALE: dict[tuple[int, int], dict] = {}


def _get_server(user_id, server_id):
    snap = STALE.get((user_id, server_id))
    if snap is not None and threading.current_thread().name.startswith("mcp-sync-"):
        return dict(snap)
    return _real_get_server(user_id, server_id)


mcp_store.get_server = _get_server
_real_apply = sync.apply


def db_row(sid):
    con = sqlite3.connect(DB)
    con.row_factory = sqlite3.Row
    r = con.execute("SELECT status, sync_status, last_error, last_synced_at FROM mcp_servers WHERE id=?", (sid,)).fetchone()
    con.close()
    return dict(r) if r else None


_N = [0]


def new_user(tag):
    _N[0] += 1
    r = cli.post("/api/auth/register", json={"username": f"race{_N[0]}", "password": "pw123456"})
    body = r.json()
    return body["user"]["id"], {"Authorization": "Bearer " + body["token"]}


def wait_idle(uid, sid, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        with sync._INFLIGHT_LOCK:
            busy = (uid, sid) in sync._INFLIGHT
        if not busy:
            return True
        time.sleep(0.01)
    return False


def disable(H, sid):
    return cli.patch(f"/api/mcp/servers/{sid}", json={"enabled": False}, headers=H)


def install_blocked(tag, mode):
    """新用户安装 Learn；后台同步卡在 tools/list 时返回。"""
    mock.arm(mode)
    uid, H = new_user(tag)
    r = cli.post("/api/plugins/microsoft_learn/install", headers=H)
    sid = (r.json().get("servers") or [{}])[0].get("id")
    arrived = mock.arrived.wait(5)
    return uid, H, sid, arrived


def race_case(name, mode, *, stale=False, crash=False):
    uid, H, sid, arrived = install_blocked(name, mode)
    if stale:
        STALE[(uid, sid)] = _real_get_server(uid, sid)       # 停用前的快照（status=needs_auth）
    if crash:
        def boom(*a, **k):
            raise RuntimeError("unexpected")
        sync.apply = boom
    turned = disable(H, sid)
    mock.release.set()
    idle = wait_idle(uid, sid)
    STALE.pop((uid, sid), None)
    sync.apply = _real_apply
    row = db_row(sid)
    listed = next((s for s in cli.get("/api/mcp/servers", headers=H).json()["servers"] if s["id"] == sid), {})
    check(name, arrived and idle and turned.status_code == 200 and row["status"] == "disabled"
          and row["sync_status"] != "syncing" and listed.get("status") == "disabled" and listed.get("enabled") is False,
          f"arrived={arrived} idle={idle} row={row} listed={ {k: listed.get(k) for k in ('status', 'sync_status')} }")
    return uid, H, sid, row


# 1) 成功分支：tools/list 进行中停用 → 放行后不能改回 connected
uid1, H1, sid1, row1 = race_case("MCP-RACE-01 success branch: disable during tools/list stays disabled", "ok")
check("MCP-RACE-01b disabled sync settles to pending, result not written",
      row1["sync_status"] == "pending" and row1["last_synced_at"] is None, str(row1))
# 2) 失败分支（503）：不能改成 error
race_case("MCP-RACE-02 failure branch: disable during tools/list, 503 does not overwrite with error", "503")
# 3) 成功分支最坏时序：停用落在「读完 current、写 connected 之前」
race_case("MCP-RACE-03 success branch, disable lands between read and write", "ok", stale=True)
# 4) 失败分支最坏时序：停用落在「读完 current、写 error 之前」
race_case("MCP-RACE-04 failure branch, disable lands between read and write", "503", stale=True)
# 5) 后台线程里的意外异常（schedule_sync 兜底写 error）
race_case("MCP-RACE-05 unexpected exception in background sync does not overwrite disabled", "ok", crash=True)

# 6) 未配置地址分支：读到未停用的行之后才停用
def install_then_unset_url(tag):
    """安装（需要地址）并同步完成后，去掉目录地址和行上记的地址，模拟「尚未配置 MCP 服务地址」。"""
    mock.block = False
    mock.list_mode = "ok"
    uid, H = new_user(tag)
    sid = (cli.post("/api/plugins/microsoft_learn/install", headers=H).json().get("servers") or [{}])[0].get("id")
    wait_idle(uid, sid)
    os.environ["VERABOT_MCP_LEARN_URL"] = ""
    mcp_store.update_server(uid, sid, url=None)
    return uid, H, sid


uid6, H6, sid6 = install_then_unset_url("nourl")
STALE[(uid6, sid6)] = _real_get_server(uid6, sid6)
disable(H6, sid6)
out6 = {}
t6 = threading.Thread(target=lambda: out6.update(sync.sync_server(uid6, sid6)), name=f"mcp-sync-{uid6}-{sid6}")
t6.start(); t6.join(10)
STALE.pop((uid6, sid6), None)
row6 = db_row(sid6)
check("MCP-RACE-06 no-URL branch: disable after read is not overwritten with error",
      row6["status"] == "disabled" and row6["sync_status"] != "syncing", str(row6))
os.environ["VERABOT_MCP_LEARN_URL"] = mock.url

# 7) 对照：不停用时三条分支照旧
mock.block = False
mock.list_mode = "ok"
uid7, H7 = new_user("ok")
sid7 = (cli.post("/api/plugins/microsoft_learn/install", headers=H7).json().get("servers") or [{}])[0].get("id")
wait_idle(uid7, sid7)
row7 = db_row(sid7)
mock.list_mode = "503"
uid8, H8 = new_user("fail")
sid8 = (cli.post("/api/plugins/microsoft_learn/install", headers=H8).json().get("servers") or [{}])[0].get("id")
wait_idle(uid8, sid8)
row8 = db_row(sid8)
uid9, H9, sid9 = install_then_unset_url("nourl2")
sync.sync_server(uid9, sid9)
row9 = db_row(sid9)
os.environ["VERABOT_MCP_LEARN_URL"] = mock.url
check("MCP-RACE-07 control without disable: connected/ok, error/error, no-URL error/error",
      row7["status"] == "connected" and row7["sync_status"] == "ok" and row7["last_synced_at"]
      and row8["status"] == "error" and row8["sync_status"] == "error" and row8["last_error"] == "MCP 服务不可用"
      and row9["status"] == "error" and row9["sync_status"] == "error" and row9["last_error"] == "尚未配置 MCP 服务地址",
      f"{row7} {row8} {row9}")

# 8) 停用后重新启用：照常重新同步并连上
mock.list_mode = "ok"
re = cli.patch(f"/api/mcp/servers/{sid1}", json={"enabled": True}, headers=H1)
deadline = time.time() + 5
while time.time() < deadline and db_row(sid1)["sync_status"] not in ("ok", "error"):
    time.sleep(0.02)
row10 = db_row(sid1)
check("MCP-RACE-08 re-enable after a discarded sync reconnects",
      re.status_code == 200 and row10["status"] == "connected" and row10["sync_status"] == "ok", str(row10))

mcp_store.get_server = _real_get_server
mock.shutdown()
print(f"\nMCP race tests failed: {len(FAILS)}")
sys.exit(1 if FAILS else 0)
