#!/usr/bin/env python3
"""多 Agent 权限 / 护栏 + BUG 修复的确定性测试（Deterministic tests）。
使用临时 SQLite 与 mock LLM，不消耗 Token、不触碰正式数据库。
运行（在 backend/ 下）：uv run python scripts/test/multi_agent_test.py
"""
import asyncio, json, os, sqlite3, sys, tempfile
from pathlib import Path

TMP = tempfile.mkdtemp(prefix="vb_ma_")
os.environ["VERABOT_DB"] = str(Path(TMP) / "t.db")
os.environ["VERABOT_DATA_DIR"] = TMP
os.environ.setdefault("DEEPSEEK_API_KEY", "test-not-used")
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))   # backend/

from verabot import db  # noqa: E402
from verabot.core import config  # noqa: E402
from verabot.services import llm  # noqa: E402

RESULTS = []
def check(cid, name, ok, note=""):
    RESULTS.append((cid, name, bool(ok), note)); print(f"[{'PASS' if ok else 'FAIL'}] {cid} {name} {note}", flush=True)

# ---------- 1. 迁移 Migration：v1 库 → v2 ----------
con = sqlite3.connect(os.environ["VERABOT_DB"]); con.executescript(db.SCHEMA)
con.execute("INSERT INTO users(id,username,password_hash,created_at) VALUES (1,'legacy','x','2026-01-01')")
for i, n in [(1, "Vera"), (2, "小研"), (3, "阿厨")]:
    con.execute("INSERT INTO bots(id,user_id,name,created_at) VALUES (?,1,?,'2026-01-01')", (i, n))
con.commit(); con.close()
db.init_db(); db.init_db()   # 幂等：执行两次
legacy = db.list_bots(1)
ok = all(b["accept_delegation"] and set(b["allowed_tools"]) == set(db.ALL_TOOLS_V2)
         and set(b["delegate_to"]) == {1, 2, 3} - {b["id"]} for b in legacy)
check("MA-01", "迁移：存量 Bot 获得全部工具且可互相委派", ok, str([(b["name"], b["delegate_to"]) for b in legacy]))

from fastapi.testclient import TestClient  # noqa: E402
from verabot.main import app  # noqa: E402
from verabot.tools.registry import ToolContext, TurnState, run_tool  # noqa: E402
cli = TestClient(app)

def reg(u):
    r = cli.post("/api/auth/register", json={"username": u, "password": "pw123456"}); return {"Authorization": "Bearer " + r.json()["token"]}, r.json()["user"]["id"]
H, UID = reg("alice"); H2, UID2 = reg("bob")

# ---------- 2. 最小权限默认值 ----------
a = cli.post("/api/bots", json={"name": "A"}, headers=H).json()
check("MA-02", "新 Bot 默认最小权限", a["allowed_tools"] == [] and a["delegate_to"] == [] and a["accept_delegation"] is False, str(a))
b = cli.post("/api/bots", json={"name": "B", "persona": "厨师", "instructions": "私有指令SECRET_INSTR"}, headers=H).json()
c = cli.post("/api/bots", json={"name": "C"}, headers=H).json()
bob_bot = cli.post("/api/bots", json={"name": "BobBot"}, headers=H2).json()

# ---------- 3. 权限配置校验 ----------
r1 = cli.patch(f"/api/bots/{a['id']}", json={"allowed_tools": ["rm_rf"]}, headers=H)
r2 = cli.patch(f"/api/bots/{a['id']}", json={"delegate_to": [bob_bot["id"]]}, headers=H)
r3 = cli.patch(f"/api/bots/{a['id']}", json={"delegate_to": [a["id"]]}, headers=H)
check("MA-03", "权限配置校验：未知工具/他人 Bot/自己 → 422", (r1.status_code, r2.status_code, r3.status_code) == (422, 422, 422),
      f"{r1.status_code},{r2.status_code},{r3.status_code}")

# ---------- 4. 未授权工具被服务端拒绝 + 审计 ----------
A = db.get_bot(UID, a["id"])
res = asyncio.run(run_tool(ToolContext(user_id=UID, bot=A), "get_weather", '{"city":"北京"}'))
n_audit = sqlite3.connect(os.environ["VERABOT_DB"]).execute(
    "SELECT COUNT(*) FROM audit_log WHERE kind='tool_denied' AND bot_id=?", (a["id"],)).fetchone()[0]
check("MA-04", "未授权工具调用被拒绝并记录 audit_log", res.get("code") == "tool_not_allowed" and n_audit == 1, str(res))

# ---------- mock LLM ----------
CAPTURE = []
async def fake_complete(messages, tools):
    CAPTURE.append({"messages": messages, "tools": [t["function"]["name"] for t in (tools or [])]})
    return {"content": "子答复OK", "_finish_reason": "stop"}, {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15}
llm.complete = fake_complete

def ask(ctx, name, shared="", q="问题Q"):
    return asyncio.run(run_tool(ctx, "ask_bot", json.dumps({"bot_name": name, "question": q, "shared_context": shared}, ensure_ascii=False)))

cli.patch(f"/api/bots/{a['id']}", json={"allowed_tools": ["ask_bot"], "delegate_to": [b["id"]]}, headers=H)
A = db.get_bot(UID, a["id"])
# ---------- 5. 委派白名单 ----------
res = ask(ToolContext(user_id=UID, bot=A), "C")
check("MA-05", "委派给白名单外的 Bot 被拒绝", res.get("code") == "not_in_allowlist", str(res))
res = ask(ToolContext(user_id=UID, bot=A), "B")
check("MA-06", "目标未开启 accept_delegation 时被拒绝", res.get("code") == "target_refuses", str(res))
cli.patch(f"/api/bots/{b['id']}", json={"accept_delegation": True}, headers=H)
res = ask(ToolContext(user_id=UID, bot=A), "BobBot")
check("MA-07", "无法委派给其他用户的 Bot（按名称也找不到）", "error" in res and "delegation_id" not in res, str(res))

# ---------- 8. 上下文隔离 + shared_context 上限 ----------
db.add_message(UID, a["id"], "user", "我的银行卡密码是 HISTORY_SECRET_999")
CAPTURE.clear()
long_shared = "背" * 5000
res = ask(ToolContext(user_id=UID, bot=A), "B", shared=long_shared)
sent = json.dumps(CAPTURE[0]["messages"], ensure_ascii=False) if CAPTURE else ""
con = sqlite3.connect(os.environ["VERABOT_DB"]); con.row_factory = sqlite3.Row
row = dict(con.execute("SELECT shared_context, shared_truncated, payload, status, total_tokens FROM delegations WHERE id=?",
                       (res.get("delegation_id"),)).fetchone())
check("MA-08", "shared_context 截断到上限并记录 truncated",
      len(row["shared_context"]) == config.MAX_SHARED_CONTEXT and row["shared_truncated"] == 1 and res.get("shared_truncated") is True,
      f"len={len(row['shared_context'])} truncated={row['shared_truncated']}")
check("MA-09", "委派不携带任何历史；目标私有 instructions 不外泄给发起方",
      "HISTORY_SECRET_999" not in sent and len(CAPTURE[0]["messages"]) == 2 and "SECRET_INSTR" not in json.dumps(res, ensure_ascii=False),
      f"msgs={len(CAPTURE[0]['messages'])}")
check("MA-10", "协作记录含 payload / 回答 / tokens / status",
      row["status"] == "ok" and row["total_tokens"] == 15 and "问题Q" in row["payload"], f"tokens={row['total_tokens']}")
check("MA-11", "被委派方（depth=1）不再获得 ask_bot 工具（默认 1 跳）", "ask_bot" not in CAPTURE[0]["tools"], str(CAPTURE[0]["tools"]))

# ---------- 12. 深度 / 环路 / 单轮上限 ----------
cli.patch(f"/api/bots/{b['id']}", json={"allowed_tools": ["ask_bot"], "delegate_to": [a["id"], c["id"]]}, headers=H)
cli.patch(f"/api/bots/{a['id']}", json={"accept_delegation": True}, headers=H)
cli.patch(f"/api/bots/{c['id']}", json={"accept_delegation": True}, headers=H)
B = db.get_bot(UID, b["id"])
res = ask(ToolContext(user_id=UID, bot=B, depth=1, chain=[a["id"]]), "C")
check("MA-12", "超过最大深度（depth=1 再委派）被拒绝", res.get("code") == "max_depth", str(res))
config.MAX_DELEGATION_DEPTH = 3   # 放宽深度，验证环路检测独立生效
res = ask(ToolContext(user_id=UID, bot=B, depth=1, chain=[a["id"]]), "A")
check("MA-13", "环路 A→B→A 被检测并阻止", res.get("code") == "loop", str(res))
config.MAX_DELEGATION_DEPTH = 1
A = db.get_bot(UID, a["id"])
res = ask(ToolContext(user_id=UID, bot=A, turn=TurnState(delegations=config.MAX_DELEGATIONS_PER_TURN)), "B")
check("MA-14", "单轮委派次数上限", res.get("code") == "turn_cap", str(res))
con = sqlite3.connect(os.environ["VERABOT_DB"])
rej = con.execute("SELECT reason, COUNT(*) FROM delegations WHERE status='rejected' GROUP BY reason").fetchall()
aud = con.execute("SELECT COUNT(*) FROM audit_log WHERE kind='delegation_rejected'").fetchone()[0]
depth_aud = con.execute("SELECT COUNT(*) FROM audit_log WHERE kind='tool_denied' AND detail LIKE '%max_depth%'").fetchone()[0]
check("MA-15", "被拒绝的委派写入 delegations(status=rejected)+audit_log；深度拦截写入 audit_log(tool_denied)",
      aud >= 4 and len(rej) >= 4 and depth_aud >= 1, f"{rej} depth_audit={depth_aud}")

# ---------- 16. 协作记录 API + 隔离 ----------
lg = cli.get(f"/api/bots/{a['id']}/delegations", headers=H).json()["delegations"]
other = cli.get(f"/api/bots/{a['id']}/delegations", headers=H2).status_code
check("MA-16", "协作记录 API 返回记录；他人访问 404", len(lg) >= 1 and other == 404, f"n={len(lg)} other={other}")

# ---------- 17. Token 预算（BUG-06） ----------
db.log_usage(UID, a["id"], "chat", {"total_tokens": 500})
con = sqlite3.connect(os.environ["VERABOT_DB"]); con.execute("UPDATE users SET token_budget=400 WHERE id=?", (UID,)); con.commit()
r = cli.post(f"/api/bots/{a['id']}/chat", json={"message": "hi"}, headers=H)
res = ask(ToolContext(user_id=UID, bot=db.get_bot(UID, a["id"])), "B")
q = cli.get("/api/quota", headers=H).json()
check("MA-17", "预算用尽：chat 429、委派拒绝(budget)、quota 显示个人预算",
      r.status_code == 429 and res.get("code") == "budget" and q["daily_token_quota"] == 400, f"{r.status_code} {r.json()}")
con.execute("UPDATE users SET token_budget=NULL WHERE id=?", (UID,)); con.commit()

# ---------- 18. 软上限 Soft limit ----------
codes = [cli.post("/api/bots", json={"name": f"S{i}"}, headers=H2).status_code for i in range(config.MAX_BOTS_PER_USER + 1)]
n = len(cli.get("/api/bots", headers=H2).json()["bots"])
check("MA-18", f">5 个 Bot 可创建，直到软上限 {config.MAX_BOTS_PER_USER}", n == config.MAX_BOTS_PER_USER and codes[-1] == 400
      and cli.get("/api/bots", headers=H2).json()["limit"] == config.MAX_BOTS_PER_USER, f"n={n} last={codes[-1]}")

# ---------- 19. BUG-02/03/04 ----------
r_blank = cli.post("/api/bots", json={"name": "   "}, headers=H)
r_trim = cli.patch(f"/api/bots/{c['id']}", json={"name": "  C2  "}, headers=H)
r_pblank = cli.patch(f"/api/bots/{c['id']}", json={"name": "  "}, headers=H)
r_dup = cli.patch(f"/api/bots/{c['id']}", json={"name": " A "}, headers=H)
r_ws = cli.post(f"/api/bots/{a['id']}/chat", json={"message": "   \n "}, headers=H)
check("MA-19", "BUG-02 空白名称 422", r_blank.status_code == 422, str(r_blank.status_code))
check("MA-20", "BUG-03 PATCH 名称 trim / 空白 422 / 同名 409", r_trim.json().get("name") == "C2" and r_pblank.status_code == 422 and r_dup.status_code == 409,
      f"{r_trim.json().get('name')!r} {r_pblank.status_code} {r_dup.status_code}")
check("MA-21", "BUG-04 纯空白消息 422", r_ws.status_code == 422, str(r_ws.status_code))

# ---------- 22. BUG-09 空回复重试 ----------
SCRIPT = []
async def fake_stream(messages, tools):
    text = SCRIPT.pop(0) if SCRIPT else ""
    if text:
        yield "delta", text
    yield "usage", {"total_tokens": 3}
    yield "finish", "stop"
llm.stream_chat = fake_stream
def sse(bot_id, msg):
    body = cli.post(f"/api/bots/{bot_id}/chat", json={"message": msg}, headers=H).text
    evs = [l[6:].strip() for l in body.splitlines() if l.startswith("event:")]
    return evs, body
SCRIPT[:] = ["", "第二次成功"]
evs, body = sse(c["id"], "你好")
check("MA-22", "BUG-09 首次空回复自动重试一次后成功", "delta" in evs and "error" not in evs and "第二次成功" in body, str(evs))
SCRIPT[:] = ["", ""]
evs, body = sse(c["id"], "你好")
last = db.recent_messages(UID, c["id"], 1)[-1]["content"]
check("MA-23", "BUG-09 连续空回复 → error 事件(empty_reply)，不再静默「（无回复）」", "error" in evs and "empty_reply" in body and last.startswith("⚠️"), f"{evs} stored={last[:20]!r}")

# ---------- 24. BUG-08 委派 prompt ----------
from verabot.agents.prompts import system_prompt  # noqa: E402
sp = system_prompt(UID, db.get_bot(UID, b["id"]), delegated_by=db.get_bot(UID, a["id"]), depth=1)
check("MA-24", "BUG-08 委派 prompt 要求不透露内部工具", "不要提及、列举或解释你的内部工具" in sp)

p = sum(1 for r in RESULTS if r[2]); print(f"\nSUMMARY {p}/{len(RESULTS)} passed")
json.dump([{"id": i, "name": n, "ok": o, "note": x} for i, n, o, x in RESULTS], open(Path(TMP) / "results.json", "w"), ensure_ascii=False)
print("RESULTS_JSON", Path(TMP) / "results.json")
sys.exit(0 if p == len(RESULTS) else 1)
