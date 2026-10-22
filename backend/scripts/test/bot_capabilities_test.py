#!/usr/bin/env python3
"""Bot 能力默认全开（schema v40）确定性测试。

临时 SQLite + TestClient，不消耗 Token、不触碰正式数据库。覆盖：
新建默认值（全部内置工具 / 接受委派 / 委派全部其他 Bot / 记忆 bot_and_global）、显式权限仍可收窄、
MCP 快照只含已连接且已同意服务的 active 工具、每 Bot 20 个 MCP 上限、新建后补齐其他 Bot 的委派白名单、
v39 → v40 存量 Bot 回填与幂等。

运行（在 backend/ 下）：uv run python scripts/test/bot_capabilities_test.py
"""
import json
import os
import sqlite3
import sys
import tempfile
from pathlib import Path

TMP = tempfile.mkdtemp(prefix="vb_cap_")
DB = str(Path(TMP) / "t.db")
os.environ["VERABOT_DB"] = DB
os.environ["VERABOT_DATA_DIR"] = TMP
os.environ.setdefault("DEEPSEEK_API_KEY", "test-not-used")
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))  # backend/

from verabot import db  # noqa: E402
from verabot.core.config import MCP_MAX_TOOLS_PER_BOT  # noqa: E402
from verabot.services.bots import default_builtin_tools  # noqa: E402

RESULTS = []


def check(cid, name, ok, note=""):
    RESULTS.append((cid, name, bool(ok), note))
    print(f"[{'PASS' if ok else 'FAIL'}] {cid} {name} {note}", flush=True)


NOW = "2026-10-22T00:00:00+00:00"
EXPECTED_BUILTINS = ["ask_bot", "create_reminder", "get_weather", "list_reminders",
                     "manage_reminder", "propose_task", "web_read_result", "web_search"]


def add_server(user_id, slug, *, status="connected", consent=True):
    con = sqlite3.connect(DB)
    cur = con.execute(
        """INSERT INTO mcp_servers(user_id, slug, source, catalog_id, name, transport, url, trust,
                                   auth_type, status, created_at, updated_at, consent_at, plugin_id)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        (user_id, slug, "catalog", slug, slug, "http", f"https://{slug}.test/mcp", "verified", "none",
         status, NOW, NOW, NOW if consent else None, slug),
    )
    server_id = cur.lastrowid
    con.commit(); con.close()
    return server_id


def add_tool(user_id, server_id, name, *, status="active"):
    full = f"mcp__{name}"
    con = sqlite3.connect(DB)
    con.execute(
        """INSERT INTO mcp_tools(server_id, user_id, mcp_name, full_name, title, description, input_schema,
                                 def_hash, risk, status, first_seen_at, last_seen_at)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?)""",
        (server_id, user_id, name, full, name, "测试工具", "{}", f"hash-{name}", "read", status, NOW, NOW),
    )
    con.commit(); con.close()
    return full


db.init_db()

from fastapi.testclient import TestClient  # noqa: E402
import verabot.api.routers.bots as bots_router  # noqa: E402
from verabot.main import app  # noqa: E402


async def _skip_opening(user_id, bot_id):   # 不调真实模型
    return None


bots_router._generate_opening_background = _skip_opening
cli = TestClient(app)


def reg(username):
    r = cli.post("/api/auth/register", json={"username": username, "password": "pw123456"})
    body = r.json()
    return {"Authorization": "Bearer " + body["token"]}, body["user"]["id"]


def create(headers, name, **perms):
    return cli.post("/api/bots", json={"name": name, **perms}, headers=headers).json()


H, ALICE = reg("alice_cap")
H2, BOB = reg("bob_cap")

check("CAP-01", "注册表内置工具集合与预期一致（新工具加入时需要更新 API 契约）",
      default_builtin_tools() == EXPECTED_BUILTINS, str(default_builtin_tools()))

# ---------- CAP-02 新 Bot 默认全开 ----------
a = create(H, "A")
check("CAP-02", "新 Bot 默认：全部内置工具、接受委派、暂无可委派对象、记忆 bot_and_global",
      a["allowed_tools"] == EXPECTED_BUILTINS and a["delegate_to"] == []
      and a["accept_delegation"] is True and a["memory_access"] == "bot_and_global",
      json.dumps({k: a.get(k) for k in ("allowed_tools", "delegate_to", "accept_delegation", "memory_access")}, ensure_ascii=False))

# ---------- CAP-03 第二个 Bot 起：互相委派 ----------
b = create(H, "B")
a_after = cli.get(f"/api/bots/{a['id']}", headers=H).json()
check("CAP-03", "新建第二个 Bot：它委派给已有 Bot，且已有 Bot 的委派白名单自动补上它",
      b["delegate_to"] == [a["id"]] and a_after["delegate_to"] == [b["id"]], f"b={b['delegate_to']} a={a_after['delegate_to']}")

# ---------- CAP-04 显式权限仍然优先（可以收窄） ----------
r = create(H, "R", allowed_tools=[], accept_delegation=False, delegate_to=[])
check("CAP-04", "创建时显式传入权限覆盖默认值：空工具 / 不接受委派 / 空委派白名单",
      r["allowed_tools"] == [] and r["accept_delegation"] is False and r["delegate_to"] == [], str(r))

# ---------- CAP-05 MCP 快照：只含已连接且已同意服务的 active 工具 ----------
s_ok = add_server(ALICE, "srvok")
add_tool(ALICE, s_ok, "srvok__alpha")
add_tool(ALICE, s_ok, "srvok__beta")
add_tool(ALICE, s_ok, "srvok__changed", status="changed")
add_tool(ALICE, s_ok, "srvok__removed", status="removed")
s_no_consent = add_server(ALICE, "srvnoconsent", consent=False)
add_tool(ALICE, s_no_consent, "srvnoconsent__tool")
s_disabled = add_server(ALICE, "srvdisabled", status="disabled")
add_tool(ALICE, s_disabled, "srvdisabled__tool")
s_bob = add_server(BOB, "bobsrv")
add_tool(BOB, s_bob, "bobsrv__tool")
d = create(H, "D")
bob_bot = create(H2, "BobBot")
expected_mcp_d = sorted({"mcp__srvok__alpha", "mcp__srvok__beta"})
check("CAP-05", "新建 Bot 的 MCP 默认：已连接+已同意+active 的工具进白名单；未同意 / 已停用 / changed / removed 不进；账号隔离",
      sorted(t for t in d["allowed_tools"] if t.startswith("mcp__")) == expected_mcp_d
      and all(t in d["allowed_tools"] for t in EXPECTED_BUILTINS)
      and sorted(t for t in bob_bot["allowed_tools"] if t.startswith("mcp__")) == ["mcp__bobsrv__tool"]
      and all(t in bob_bot["allowed_tools"] for t in EXPECTED_BUILTINS),
      f"d={d['allowed_tools']} bob={bob_bot['allowed_tools']}")

# ---------- CAP-06 每 Bot MCP 工具上限 20（按工具全名排序截断） ----------
s_big = add_server(ALICE, "srvbig")
for i in range(25):
    add_tool(ALICE, s_big, f"srvbig__t{i:02d}")
e = create(H, "E")
all_active = sorted({"mcp__srvok__alpha", "mcp__srvok__beta", *[f"mcp__srvbig__t{i:02d}" for i in range(25)]})
e_mcp = sorted(t for t in e["allowed_tools"] if t.startswith("mcp__"))
check("CAP-06", f"MCP 工具截断到每 Bot {MCP_MAX_TOOLS_PER_BOT} 个（排序后取前 N，结果确定）",
      e_mcp == all_active[:MCP_MAX_TOOLS_PER_BOT] and len(e_mcp) == MCP_MAX_TOOLS_PER_BOT, f"n={len(e_mcp)}")

# ---------- CAP-07 新建 Bot 后补齐其他 Bot 的委派白名单（只给开启 ask_bot 的 Bot） ----------
a_now = cli.get(f"/api/bots/{a['id']}", headers=H).json()
d_now = cli.get(f"/api/bots/{d['id']}", headers=H).json()
r_now = cli.get(f"/api/bots/{r['id']}", headers=H).json()
check("CAP-07", "新 Bot 自动补进开启 ask_bot 的其他 Bot 委派白名单；未开启 ask_bot 的 Bot 不被改动",
      sorted(a_now["delegate_to"]) == sorted([b["id"], d["id"], e["id"]])
      and e["id"] in d_now["delegate_to"] and r_now["delegate_to"] == [], f"a={a_now['delegate_to']} r={r_now['delegate_to']}")

# ---------- CAP-08 v39 → v40：存量 Bot 一并打开（含记忆授权）且幂等 ----------
con = sqlite3.connect(DB)
con.execute("UPDATE bots SET allowed_tools='[]', delegate_to='[]', accept_delegation=0, memory_access='none' WHERE user_id=?",
            (ALICE,))
con.execute("UPDATE schema_meta SET value='39' WHERE key='version'")
con.commit(); con.close()
db.init_db()
con = sqlite3.connect(DB); con.row_factory = sqlite3.Row
bots = {row["id"]: dict(row) for row in con.execute(
    "SELECT id, allowed_tools, delegate_to, accept_delegation, memory_access FROM bots WHERE user_id=? ORDER BY id",
    (ALICE,))}
ver = con.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()[0]
con.close()
ids = sorted(bots)
expected_allowed = sorted(set(EXPECTED_BUILTINS) | set(all_active[:MCP_MAX_TOOLS_PER_BOT]))
ok = ver == "40"
for bid, row in bots.items():
    ok = ok and json.loads(row["allowed_tools"]) == expected_allowed \
        and json.loads(row["delegate_to"]) == [x for x in ids if x != bid] \
        and row["accept_delegation"] == 1 and row["memory_access"] == "bot_and_global"
check("CAP-08", "v39 → v40：存量 Bot 的工具 / 委派 / 接受委派 / 记忆授权全部打开",
      ok, f"ver={ver} sample={ {k: (v['allowed_tools'], v['delegate_to'], v['accept_delegation'], v['memory_access']) for k, v in list(bots.items())[:1]} }")

before = {bid: dict(row) for bid, row in bots.items()}
db.init_db()
con = sqlite3.connect(DB); con.row_factory = sqlite3.Row
after = {row["id"]: dict(row) for row in con.execute(
    "SELECT id, allowed_tools, delegate_to, accept_delegation, memory_access FROM bots WHERE user_id=? ORDER BY id",
    (ALICE,))}
con.close()
check("CAP-09", "v40 迁移幂等：重复启动不改写已回填的权限", before == {k: dict(v) for k, v in after.items()}, "")

# ---------- CAP-10 创建后仍可通过 PATCH 收窄 ----------
patched = cli.patch(f"/api/bots/{e['id']}", json={"allowed_tools": ["get_weather"], "delegate_to": []}, headers=H)
check("CAP-10", "PATCH 仍可显式收窄工具与委派白名单（默认全开不等于锁死）",
      patched.status_code == 200 and patched.json()["allowed_tools"] == ["get_weather"]
      and patched.json()["delegate_to"] == [], patched.text[:200])

# ---------- CAP-11 客户端契约：iOS / Web 创建 Bot 不传权限字段，由服务端套用默认值 ----------
root = Path(__file__).resolve().parents[3]
models = (root / "frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore/Models.swift").read_text()
create_struct = models.split("public struct BotCreate", 1)[1].split("\n}", 1)[0]
web = (root / "frontend/web/app.js").read_text()
web_create = web.split('api("/api/bots", { method: "POST"', 1)[1].split("})", 1)[0]
check("CAP-11", "契约：iOS BotCreate / Web 创建请求都不带 allowed_tools / delegate_to / accept_delegation（走服务端默认）",
      "allowedTools" not in create_struct and "allowed_tools" not in create_struct
      and "allowed_tools" not in web_create and "accept_delegation" not in web_create,
      f"ios_has_perms={'allowed_tools' in create_struct} web_has_perms={'allowed_tools' in web_create}")

p = sum(1 for r in RESULTS if r[2])
print(f"\nSUMMARY {p}/{len(RESULTS)} passed")
json.dump([{"id": i, "name": n, "ok": o, "note": x} for i, n, o, x in RESULTS],
          open(Path(TMP) / "results.json", "w"), ensure_ascii=False)
sys.exit(0 if p == len(RESULTS) else 1)
