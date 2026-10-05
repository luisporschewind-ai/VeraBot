#!/usr/bin/env python3
"""记忆 M2（滚动摘要 + 风格校准，schema v14）确定性测试 MEM-40 ~ MEM-50。
临时 SQLite + mock LLM，不消耗 Token、不触碰正式数据库。
运行（在 backend/ 下）：uv run python scripts/test/memory_m2_test.py
"""
import json, os, sqlite3, sys, tempfile
from pathlib import Path

TMP = tempfile.mkdtemp(prefix="vb_mem2_")
DB = str(Path(TMP) / "t.db")
os.environ["VERABOT_DB"] = DB
os.environ["VERABOT_DATA_DIR"] = TMP
os.environ.pop("VERABOT_MEMORY_ENC_KEY", None)
os.environ.setdefault("DEEPSEEK_API_KEY", "test-not-used")
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))   # backend/

RESULTS = []
def check(cid, name, ok, note=""):
    RESULTS.append((cid, name, bool(ok), note)); print(f"[{'PASS' if ok else 'FAIL'}] {cid} {name} {note}", flush=True)

from verabot import db  # noqa: E402
from verabot.core import config  # noqa: E402
from verabot.db import memory_job_store as jstore  # noqa: E402
from verabot.services import llm  # noqa: E402
from verabot.services.memory import jobs as mjobs  # noqa: E402

# ---------- MEM-40 迁移 v13 → v14 ----------
db.init_db(); db.init_db()   # 幂等
con = sqlite3.connect(DB); con.row_factory = sqlite3.Row
ver = con.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()[0]
tables = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}
job_cols = {r[1] for r in con.execute("PRAGMA table_info(memory_jobs)")}
fb_cols = {r[1] for r in con.execute("PRAGMA table_info(message_feedback)")}
idx = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='index'")}
con.close()
check("MEM-40", "v13 → v14 迁移幂等：memory_jobs + message_feedback 表与索引",
      ver == str(db.SCHEMA_VERSION) == "14" and {"memory_jobs", "message_feedback"} <= tables
      and {"kind", "status", "after_message_id", "attempts", "finished_at"} <= job_cols
      and {"rating", "reason", "message_id", "updated_at"} <= fb_cols and "idx_memjob_open" in idx, f"ver={ver}")

from fastapi.testclient import TestClient  # noqa: E402
from verabot.main import app  # noqa: E402
cli = TestClient(app)

def reg(u):
    r = cli.post("/api/auth/register", json={"username": u, "password": "pw123456"}).json()
    return {"Authorization": "Bearer " + r["token"]}, r["user"]["id"]
H, UID = reg("alice"); H2, UID2 = reg("bob")
vera = cli.post("/api/bots", json={"name": "Vera"}, headers=H).json()
other = cli.post("/api/bots", json={"name": "小研"}, headers=H).json()

def q(sql, *a):
    c = sqlite3.connect(DB); c.row_factory = sqlite3.Row
    try:
        return [dict(r) for r in c.execute(sql, a).fetchall()]
    finally:
        c.close()

# ---------- mock LLM ----------
CALLS, PLAN = [], []
async def fake_stream(messages, tools):
    CALLS.append({"system": messages[0]["content"], "tools": [t["function"]["name"] for t in (tools or [])]})
    step = PLAN.pop(0) if PLAN else "好的"
    if isinstance(step, str):
        yield "delta", step
    else:
        yield "tool_calls", [{"id": f"c{len(CALLS)}_{i}", "name": n, "arguments": json.dumps(a, ensure_ascii=False)}
                             for i, (n, a) in enumerate(step)]
    yield "usage", {"prompt_tokens": 10, "completion_tokens": 2, "total_tokens": 12}
    yield "finish", "stop"

SUMMARY_JSON = json.dumps({"summary": "用户在准备搬家，决定周末看房；助理答应整理清单。",
                           "open_items": ["整理搬家清单"]}, ensure_ascii=False)
DCALLS, DMODE = [], {"reply": SUMMARY_JSON}
async def fake_complete(messages, tools, **kw):
    DCALLS.append({"messages": messages, "tools": tools, "kw": kw})
    if isinstance(DMODE["reply"], Exception):
        raise DMODE["reply"]
    return {"content": DMODE["reply"], "_finish_reason": "stop"}, {"total_tokens": 30}

llm.stream_chat = fake_stream
llm.complete = fake_complete

def sse(bot_id, msg="你好", headers=None, plan=None):
    PLAN[:] = plan or []
    body = cli.post(f"/api/bots/{bot_id}/chat", json={"message": msg}, headers=headers or H).text
    evs, cur = [], None
    for line in body.splitlines():
        if line.startswith("event:"):
            cur = line[6:].strip()
        elif line.startswith("data:"):
            evs.append((cur, json.loads(line[5:].strip())))
    return evs

def results(evs, name=None):
    return [d["result"] for e, d in evs if e == "tool_result" and (name is None or d["name"] == name)]

def done(evs):
    return next((d for e, d in evs if e == "done"), {})

def style_cards(evs):
    return [d["result"] for e, d in evs if e == "tool_result" and d["name"] == "remember"
            and (d["result"] or {}).get("type") == "style"]

# ---------- MEM-41 入队 + 阈值 ----------
sse(vera["id"], "第一轮")
jobs = q("SELECT * FROM memory_jobs WHERE user_id=?", UID)
n = mjobs.run_once()   # 消息不足 → skipped（不调用 LLM）
row = q("SELECT * FROM memory_jobs WHERE user_id=? ORDER BY id DESC LIMIT 1", UID)[0]
check("MEM-41", "run_chat 结束入队 summarize；窗口外不足 20 条 → skipped（不调用 LLM）",
      len(jobs) == 1 and jobs[0]["kind"] == "summarize" and jobs[0]["status"] == "pending"
      and n == 1 and row["status"] == "skipped" and row["error"] == "insufficient" and not DCALLS,
      f"jobs={len(jobs)} status={row['status']}/{row['error']}")

# ---------- MEM-42 摘要生成：≤400 字、只服务本 Bot ----------
for i in range(45):    # 直接写库，凑够窗口外 ≥20 条
    db.add_message(UID, vera["id"], "user" if i % 2 == 0 else "assistant", f"较早的消息 {i}")
db.add_message(UID, other["id"], "user", "别的 Bot 的消息")
mjobs.enqueue_summarize(UID, vera["id"], None)
DCALLS.clear()
n = mjobs.run_once()
sm = q("SELECT * FROM memories WHERE user_id=? AND scope='summary'", UID)
meta = json.loads(sm[0]["meta"]) if sm else {}
check("MEM-42", "窗口外累计 ≥20 条 → 生成 1 条 scope='summary' 的 active 记忆（≤400 字，meta 记 covers_until）",
      n == 1 and len(sm) == 1 and sm[0]["type"] == "summary" and sm[0]["status"] == "active"
      and sm[0]["source"] == "summary_job" and sm[0]["bot_id"] == vera["id"]
      and len(sm[0]["content"]) <= config.MEMORY_SUMMARY_MAX_CHARS
      and meta.get("covers_until_message_id") and "整理搬家清单" in sm[0]["content"],
      f"summary={(sm[0]['content'][:36] if sm else None)}")
check("MEM-42b", "摘要请求走 JSON Output（response_format=json_object），只读本 Bot 的消息",
      DCALLS and DCALLS[0]["kw"].get("json_object") is True and DCALLS[0]["tools"] is None
      and "别的 Bot" not in json.dumps(DCALLS[0]["messages"], ensure_ascii=False))

# ---------- MEM-43 注入：摘要接在记忆块之后，只给本 Bot ----------
CALLS.clear()
sse(vera["id"], "继续")
sys_vera = CALLS[-1]["system"]
sse(other["id"], "你好")
sys_other = CALLS[-1]["system"]
after_block = "</user_memory>" not in sys_vera or sys_vera.index("【较早对话摘要】") > sys_vera.index("</user_memory>")
check("MEM-43", "摘要注入（记忆块之后），且只注入给本条对话的 Bot",
      "【较早对话摘要】" in sys_vera and "搬迁" not in sys_vera and after_block
      and "【较早对话摘要】" not in sys_other)

# ---------- MEM-44 清空对话删除摘要 ----------
r = cli.delete(f"/api/bots/{vera['id']}/messages", params={"include_memories": "true"}, headers=H).json()
left = q("SELECT COUNT(*) AS n FROM memories WHERE user_id=? AND scope='summary'", UID)[0]["n"]
check("MEM-44", "清空对话（include_memories=true）删除该 Bot 的摘要",
      r["deleted_memories"] >= 1 and left == 0, f"deleted={r['deleted_memories']} left={left}")

# ---------- MEM-45 失败重试 ≤ 上限 ----------
for i in range(45):
    db.add_message(UID, vera["id"], "user" if i % 2 == 0 else "assistant", f"消息 {i}")
DMODE["reply"] = "这不是 json"
mjobs.enqueue_summarize(UID, vera["id"], None)
for _ in range(6):
    mjobs.run_once()
job = q("SELECT * FROM memory_jobs WHERE user_id=? AND bot_id=? AND kind='summarize' ORDER BY id DESC LIMIT 1",
        UID, vera["id"])[0]
check("MEM-45", "摘要输出不是 JSON → 重试到上限后 failed（error=bad_json）",
      job["status"] == "failed" and job["error"] == "bad_json"
      and job["attempts"] == config.MEMORY_JOBS_MAX_ATTEMPTS, f"{job['status']}/{job['error']} attempts={job['attempts']}")
DMODE["reply"] = SUMMARY_JSON

# ---------- MEM-46 预算 ≥ 90% → skipped ----------
c = sqlite3.connect(DB); c.execute("UPDATE users SET token_budget=1000 WHERE id=?", (UID,))
c.execute("INSERT INTO usage_log(user_id,bot_id,kind,total_tokens,created_at) VALUES (?,?,?,?,?)",
          (UID, vera["id"], "chat", 950, db.now_iso())); c.commit(); c.close()
DCALLS.clear()
mjobs.enqueue_summarize(UID, vera["id"], None)
mjobs.run_once()
job = q("SELECT * FROM memory_jobs WHERE user_id=? AND bot_id=? AND kind='summarize' ORDER BY id DESC LIMIT 1",
        UID, vera["id"])[0]
check("MEM-46", "当日用量 ≥ 90% 预算 → 摘要 skipped（不调用 LLM）",
      job["status"] == "skipped" and job["error"] == "budget" and not DCALLS, f"{job['status']}/{job['error']}")
c = sqlite3.connect(DB); c.execute("UPDATE users SET token_budget=NULL WHERE id=?", (UID,)); c.commit(); c.close()

# ---------- MEM-47 重启恢复 ----------
mjobs.enqueue_summarize(UID, other["id"], None)   # 造一条 pending（别的 Bot 的，不会被摘要消费）
c = sqlite3.connect(DB); c.execute("UPDATE memory_jobs SET status='running' WHERE status='pending'"); c.commit(); c.close()
with db.tx() as cc:
    recovered = jstore.recover_running(cc)
check("MEM-47", "启动时遗留的 running 任务退回 pending（重启安全）", recovered >= 1, f"recovered={recovered}")

# ---------- MEM-48 反馈写入 / 改评 / 撤销 / 越权 ----------
evs = sse(vera["id"], "给我讲讲")
mid = done(evs)["message_id"]
r1 = cli.post(f"/api/messages/{mid}/feedback", json={"rating": 1}, headers=H).json()
row1 = q("SELECT * FROM message_feedback WHERE user_id=? AND message_id=?", UID, mid)
r2 = cli.post(f"/api/messages/{mid}/feedback", json={"rating": -1, "reason": "too_long"}, headers=H).json()
row2 = q("SELECT * FROM message_feedback WHERE user_id=? AND message_id=?", UID, mid)
lst = cli.get(f"/api/bots/{vera['id']}/messages", headers=H).json()["messages"]
mine = next(m for m in lst if m["id"] == mid)
r_pos = cli.post(f"/api/messages/{mid}/feedback", json={"rating": 1, "reason": "too_long"}, headers=H).json()
r404 = cli.post(f"/api/messages/{mid}/feedback", json={"rating": 1}, headers=H2)
rdel = cli.delete(f"/api/messages/{mid}/feedback", headers=H).json()
check("MEM-48", "👍 / 👎 写入 message_feedback（同一条可改、👍 不带理由）；他人消息 404；DELETE 撤销",
      r1["ok"] and len(row1) == 1 and row1[0]["rating"] == 1 and row1[0]["reason"] is None
      and len(row2) == 1 and row2[0]["rating"] == -1 and row2[0]["reason"] == "too_long"
      and row2[0]["id"] == row1[0]["id"] and mine["feedback"]["rating"] == -1 and r_pos["reason"] is None
      and r404.status_code == 404 and rdel["deleted"] == 1
      and not q("SELECT * FROM message_feedback WHERE user_id=? AND message_id=?", UID, mid))

# ---------- MEM-49 规则命中「用英文」→ 本轮追加合成 remember 卡片 ----------
evs = sse(vera["id"], "以后请用英文回答")
cards = style_cards(evs)
stored = json.loads(q("SELECT traces FROM messages WHERE user_id=? AND id=?", UID, done(evs)["message_id"])[0]["traces"] or "[]")
again = style_cards(sse(vera["id"], "用英文回答我"))
check("MEM-49", "规则命中 → 服务器追加合成 remember trace（proposed / bot / 风格），落库并去重",
      cards and cards[-1]["status"] == "proposed" and cards[-1]["scope"] == "bot"
      and "英文" in (cards[-1]["content"] or "")
      and any(t["name"] == "remember" and (t["result"] or {}).get("type") == "style" for t in stored)
      and not again, f"cards={len(cards)} again={len(again)}")
check("MEM-49b", "风格提议的卡片标题数据（type=style）与记忆行字段一致",
      cards and (lambda r: r and r[0]["status"] == "proposed" and r[0]["source"] == "feedback"
                 and r[0]["expires_at"])(q("SELECT * FROM memories WHERE id=?", cards[-1]["memory_id"])))
style_id = cards[-1]["memory_id"] if cards else None

# ---------- MEM-50 14 天内 3 次「太长」→ 提议；style 注入在记忆块最前 ----------
msgs = [done(sse(vera["id"], f"问题 {i}"))["message_id"] for i in range(3)]
props = [cli.post(f"/api/messages/{m}/feedback", json={"rating": -1, "reason": "too_long"}, headers=H).json()
         for m in msgs]
sty = q("SELECT * FROM memories WHERE user_id=? AND type='style'", UID)
agg = [s for s in sty if "简短" in s["content"]]      # 聚合提议（规则命中的那条是「用英文回答」）
cli.post(f"/api/memories/{style_id}/confirm", headers=H) if style_id else None
cli.post("/api/memories", json={"content": "用户住在北京", "type": "profile", "scope": "global"}, headers=H)
CALLS.clear()
sse(vera["id"], "你好")
block = CALLS[-1]["system"]
inject = block[block.index("<user_memory>"):block.index("</user_memory>")] if "<user_memory>" in block else ""
check("MEM-50", "14 天内 3 次 👎「太长」→ 第 3 次返回 style 提议；确认后 style 注入在记忆块最前",
      props[0]["proposal"] is None and props[1]["proposal"] is None and props[2]["proposal"] is not None
      and len(agg) == 1 and agg[0]["status"] == "proposed" and agg[0]["source"] == "feedback"
      and agg[0]["scope"] == "bot" and agg[0]["bot_id"] == vera["id"] and agg[0]["expires_at"]
      and "风格" in inject and inject.index("风格") < inject.index("资料"),
      f"props={[bool(p['proposal']) for p in props]} inject={inject[:60]!r}")

# ---------- 汇总 ----------
bad = [r for r in RESULTS if not r[2]]
print(f"\n{len(RESULTS) - len(bad)}/{len(RESULTS)} 通过")
sys.exit(1 if bad else 0)
