#!/usr/bin/env python3
"""记忆 M2（schema v14）：滚动摘要 + 风格校准。MEM-40 ~ MEM-49。

临时 SQLite + mock LLM，不访问 DeepSeek、不碰正式库。
运行（在 backend/ 下）：uv run python scripts/test/memory_m2_test.py
"""
import asyncio, io, json, logging, os, sqlite3, sys, tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

TMP = tempfile.mkdtemp(prefix="vb_m2_")
os.environ["VERABOT_DB"] = str(Path(TMP) / "t.db")
os.environ["VERABOT_DATA_DIR"] = TMP
os.environ["VERABOT_MEMORY_JOBS"] = "0"          # 本套件手动 process_one，不让后台 worker 抢任务
os.environ.setdefault("DEEPSEEK_API_KEY", "test-not-used")
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

RESULTS = []


def check(cid, name, ok, note=""):
    RESULTS.append((cid, name, bool(ok), note))
    print(f"[{'PASS' if ok else 'FAIL'}] {cid} {name} {note}", flush=True)


LOGBUF = io.StringIO()
_h = logging.StreamHandler(LOGBUF)
_h.setLevel(logging.DEBUG)
logging.getLogger().addHandler(_h)
logging.getLogger().setLevel(logging.INFO)

from verabot import db  # noqa: E402
from verabot.core import config  # noqa: E402
from verabot.services import llm, memory  # noqa: E402
from verabot.services.memory import jobs, style, summarize  # noqa: E402
from verabot.services.memory.jobs import process_one  # noqa: E402

db.init_db()
db.init_db()
con = sqlite3.connect(os.environ["VERABOT_DB"])
ver = con.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()[0]
tables = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}
job_cols = {r[1] for r in con.execute("PRAGMA table_info(memory_jobs)")}
fb_cols = {r[1] for r in con.execute("PRAGMA table_info(message_feedback)")}
con.close()
needed_jobs = {"id", "user_id", "bot_id", "kind", "status", "after_message_id", "attempts", "error", "created_at", "finished_at"}
needed_fb = {"id", "user_id", "bot_id", "message_id", "rating", "reason", "created_at"}
check("MEM-40", "schema v14：memory_jobs / message_feedback 建表且二次启动幂等",
      ver == "14" == str(db.SCHEMA_VERSION) and needed_jobs <= job_cols and needed_fb <= fb_cols, f"ver={ver}")

with db.tx() as c:
    c.execute("DROP TABLE memory_jobs")
    c.execute("DROP TABLE message_feedback")
    c.execute("UPDATE schema_meta SET value='13' WHERE key='version'")
db.init_db()
con = sqlite3.connect(os.environ["VERABOT_DB"])
ver2 = con.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()[0]
tables2 = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}
con.close()
check("MEM-40b", "v13 库补上两张表后版本为 14",
      ver2 == "14" and {"memory_jobs", "message_feedback"} <= tables2, ver2)

# 纯函数：窗口外未覆盖条数、摘要长度
msgs40 = [{"id": i, "role": "user", "content": "x"} for i in range(1, 41)]
back = summarize.backlog(msgs40, 0, config.HISTORY_WINDOW, config.MEMORY_SUMMARY_MIN)
check("MEM-41a", "窗口外未覆盖不足 20 条则不摘要；恰好 20 条才进入批次",
      summarize.backlog(msgs40[:39], 0, 20, 20) is None and back and len(back) == 20 and back[0]["id"] == 1
      and summarize.backlog(msgs40, 20, 20, 20) is None)
long = summarize.compose({"summary": "甲" * 500, "open_items": ["买票"]})
check("MEM-41b", "摘要压缩结果不超过 400 字", len(long) == 400 and long.startswith("甲"), str(len(long)))
check("MEM-47a", "「再短一点 / 用英文」规则命中；普通闲聊不命中",
      style.match_style("请再短一点") == config.MEMORY_STYLE_SHORTER
      and style.match_style("用英文说") == "用英文回答" and style.match_style("今天天气怎么样") is None)

from fastapi.testclient import TestClient  # noqa: E402
from verabot.main import app  # noqa: E402

cli = TestClient(app)
JSON_CALLS = []
PLAN_JSON = []


async def fake_json(messages, *, max_tokens=1024):
    JSON_CALLS.append({"n": len(messages)})
    return PLAN_JSON.pop(0), {"prompt_tokens": 100, "completion_tokens": 20, "total_tokens": 120}


async def fake_stream(messages, tools):
    yield "delta", "好的"
    yield "usage", {"prompt_tokens": 10, "completion_tokens": 2, "total_tokens": 12}
    yield "finish", "stop"


async def fake_complete(messages, tools):
    return {"content": "子答复", "_finish_reason": "stop"}, {"total_tokens": 5}


llm.complete_json = fake_json
llm.stream_chat = fake_stream
llm.complete = fake_complete


def reg(name):
    r = cli.post("/api/auth/register", json={"username": name, "password": "pw123456"}).json()
    return {"Authorization": "Bearer " + r["token"]}, r["user"]["id"]


H, UID = reg("m2a")
H2, UID2 = reg("m2b")


def q(sql, *a):
    c = sqlite3.connect(os.environ["VERABOT_DB"])
    c.row_factory = sqlite3.Row
    try:
        return [dict(r) for r in c.execute(sql, a).fetchall()]
    finally:
        c.close()


def bot(name, headers=None):
    return cli.post("/api/bots", json={"name": name}, headers=headers or H).json()


def fill(uid, bot_id, n):
    return [db.add_message(uid, bot_id, "user" if i % 2 == 0 else "assistant", f"第{i}句闲聊") for i in range(n)]


def sse(bot_id, msg, headers=None):
    body = cli.post(f"/api/bots/{bot_id}/chat", json={"message": msg}, headers=headers or H).text
    evs, cur = [], None
    for line in body.splitlines():
        if line.startswith("event:"):
            cur = line[6:].strip()
        elif line.startswith("data:"):
            evs.append((cur, json.loads(line[5:].strip())))
    return evs


B = bot("Vera")
anchor = db.add_message(UID, B["id"], "user", "锚点")
jid1 = jobs.enqueue(UID, B["id"], kind="summarize", after_message_id=None)
jid2 = jobs.enqueue(UID, B["id"], kind="summarize", after_message_id=anchor)
nrows = q("SELECT id, status, after_message_id FROM memory_jobs WHERE user_id=? AND bot_id=? AND kind='summarize'", UID, B["id"])
check("MEM-41c", "同一 Bot 的 summarize 入队幂等：已有 pending 只前移 after_message_id",
      jid1 == jid2 and len(nrows) == 1 and nrows[0]["after_message_id"] == anchor and nrows[0]["status"] == "pending",
      str(nrows))

# 不够阈值 → skipped，不调模型
fill(UID, B["id"], 10)
asyncio.run(process_one())
skipped = q("SELECT status, error FROM memory_jobs WHERE id=?", jid1)[0]
check("MEM-41d", "窗口外积压不够时 job 为 skipped，不调用摘要模型",
      skipped == {"status": "skipped", "error": "below_threshold"} and JSON_CALLS == [], str(skipped))

# 40 条：窗口外 20 条，真正摘要；只注入本 Bot；再跑一次仍只有一条摘要
S = bot("摘要Bot")
fill(UID, S["id"], 40)
jobs.enqueue(UID, S["id"], kind="summarize", after_message_id=1)
PLAN_JSON[:] = [json.dumps({"summary": "甲乙丙丁摘要周末去杭州", "open_items": []}, ensure_ascii=False)]
asyncio.run(process_one())
done = q("SELECT status, error FROM memory_jobs WHERE bot_id=? AND kind='summarize' ORDER BY id DESC LIMIT 1", S["id"])[0]
sums = q("SELECT id, content, scope, type, source, status, meta FROM memories WHERE user_id=? AND bot_id=? AND scope='summary'", UID, S["id"])
usage = q("SELECT kind, total_tokens FROM usage_log WHERE user_id=? AND bot_id=? AND kind='memory'", UID, S["id"])
other = bot("别的Bot")
block_s = memory.recall(UID, db.get_bot(UID, S["id"]), "继续").block
block_o = memory.recall(UID, db.get_bot(UID, other["id"]), "继续").block
check("MEM-41", "满 20 条窗口外消息才摘要；≤400 字；usage.kind=memory；只注入本 Bot",
      done["status"] == "done" and len(sums) == 1 and sums[0]["content"] == "甲乙丙丁摘要周末去杭州"
      and sums[0]["type"] == "summary" and sums[0]["source"] == "summary_job" and sums[0]["status"] == "active"
      and "covers_until_message_id" in (sums[0]["meta"] or "")
      and usage and usage[0]["kind"] == "memory"
      and "【较早对话摘要】甲乙丙丁摘要周末去杭州" in block_s and "甲乙丙丁摘要" not in block_o,
      f"done={done} n={len(sums)} usage={usage}")

# 再积压 20 条：更新同一条，不新插
fill(UID, S["id"], 20)
jobs.enqueue(UID, S["id"], kind="summarize")
PLAN_JSON[:] = [json.dumps({"summary": "更新后的杭州行程", "open_items": ["买票"]}, ensure_ascii=False)]
asyncio.run(process_one())
sums2 = q("SELECT id, content FROM memories WHERE user_id=? AND bot_id=? AND scope='summary' AND status='active'", UID, S["id"])
check("MEM-41e", "再次摘要更新同一条滚动摘要，不新增多余行",
      len(sums2) == 1 and sums2[0]["id"] == sums[0]["id"] and "杭州行程" in sums2[0]["content"], str(sums2))

# 清空对话删摘要、保留已确认记忆
fact = cli.post("/api/memories", json={"content": "用户喜欢爵士乐M2", "type": "preference", "scope": "bot", "bot_id": S["id"]}, headers=H).json()
cl = cli.delete(f"/api/bots/{S['id']}/messages", headers=H).json()
left_fact = q("SELECT status FROM memories WHERE id=?", fact["id"])
left_sum = q("SELECT id FROM memories WHERE bot_id=? AND scope='summary'", S["id"])
check("MEM-42", "清空对话删除摘要、保留已确认记忆",
      cl.get("ok") is True and cl.get("deleted_memories", 0) >= 1 and left_fact == [{"status": "active"}] and left_sum == [],
      f"{cl} fact={left_fact}")

# 失败重试 ≤ 2 次（共 3 次领取）后 failed
R = bot("重试Bot")
fill(UID, R["id"], 40)
jobs.enqueue(UID, R["id"], kind="summarize")


async def boom(messages, *, max_tokens=1024):
    raise llm.LLMError("boom")


llm.complete_json = boom
for _ in range(3):
    asyncio.run(process_one())
failed = q("SELECT status, attempts, error FROM memory_jobs WHERE bot_id=? AND kind='summarize'", R["id"])[0]
asyncio.run(process_one())  # 没有 pending 了
still = q("SELECT status, attempts FROM memory_jobs WHERE bot_id=? AND kind='summarize'", R["id"])[0]
check("MEM-43", "摘要失败最多再试 2 次，第 3 次领取后为 failed",
      failed["status"] == "failed" and failed["attempts"] == 3 and failed["error"] == "llm_error"
      and still["attempts"] == 3 and "甲乙丙丁" not in LOGBUF.getvalue(), str(failed))

# 预算 ≥ 90% → skipped，不调模型
llm.complete_json = fake_json
JSON_CALLS.clear()
U = bot("预算Bot")
fill(UID, U["id"], 40)
db.log_usage(UID, U["id"], "chat", {"prompt_tokens": 180000, "completion_tokens": 0, "total_tokens": 180000})
jobs.enqueue(UID, U["id"], kind="summarize")
asyncio.run(process_one())
bud = q("SELECT status, error FROM memory_jobs WHERE bot_id=? ORDER BY id DESC LIMIT 1", U["id"])[0]
mem_usage = q("SELECT id FROM usage_log WHERE user_id=? AND bot_id=? AND kind='memory'", UID, U["id"])
check("MEM-44", "当日用量 ≥ 90% 时摘要 skipped，不记 memory 用量",
      bud == {"status": "skipped", "error": "budget"} and JSON_CALLS == [] and mem_usage == [], str(bud))

# ---------- 反馈契约 ----------
asst = db.add_message(UID, B["id"], "assistant", "这是一条很长的回答")
user_msg = db.add_message(UID, B["id"], "user", "你好")
bob_asst = db.add_message(UID2, bot("Bob", H2)["id"], "assistant", "bob")
ok_up = cli.post(f"/api/messages/{asst}/feedback", json={"rating": 1}, headers=H)
bad_reason = cli.post(f"/api/messages/{asst}/feedback", json={"rating": 1, "reason": "too_long"}, headers=H)
changed = cli.post(f"/api/messages/{asst}/feedback", json={"rating": -1, "reason": "tone"}, headers=H).json()
listed = cli.get(f"/api/bots/{B['id']}/messages", headers=H).json()["messages"]
hit = next(m for m in listed if m["id"] == asst)
user_hit = next(m for m in listed if m["id"] == user_msg)
n_rows = q("SELECT rating, reason FROM message_feedback WHERE user_id=? AND message_id=?", UID, asst)
miss_user = cli.post(f"/api/messages/{user_msg}/feedback", json={"rating": 1}, headers=H)
miss_other = cli.post(f"/api/messages/{asst}/feedback", json={"rating": 1}, headers=H2)
miss_bob = cli.post(f"/api/messages/{bob_asst}/feedback", json={"rating": -1, "reason": "other"}, headers=H)
cleared = cli.delete(f"/api/messages/{asst}/feedback", headers=H)
after = cli.get(f"/api/bots/{B['id']}/messages", headers=H).json()["messages"]
after_hit = next(m for m in after if m["id"] == asst)
check("MEM-45", "反馈可改、列表回显；只评本人 assistant；撤销后为空",
      ok_up.status_code == 200 and bad_reason.status_code == 422 and changed["feedback"] == {"message_id": asst, "rating": -1, "reason": "tone"}
      and hit["feedback"] == {"rating": -1, "reason": "tone"} and user_hit["feedback"] is None and len(n_rows) == 1
      and miss_user.status_code == 404 and miss_other.status_code == 404 and miss_bob.status_code == 404
      and cleared.status_code == 200 and after_hit["feedback"] is None,
      f"up={ok_up.status_code} bad={bad_reason.status_code} other={miss_other.status_code}")

# 14 天内 3 次 too_long → 提议；窗口外的不算；只提议不生效
P = bot("风格Bot")
old = (datetime.now(timezone.utc) - timedelta(days=20)).isoformat(timespec="seconds")
old_ids = [db.add_message(UID, P["id"], "assistant", f"旧回答{i}") for i in range(3)]
for mid in old_ids:
    cli.post(f"/api/messages/{mid}/feedback", json={"rating": -1, "reason": "too_long"}, headers=H)
with db.tx() as c:
    c.execute("UPDATE message_feedback SET created_at=? WHERE message_id IN (?,?,?)", (old, *old_ids))
recent = [db.add_message(UID, P["id"], "assistant", f"新回答{i}") for i in range(3)]
r0 = cli.post(f"/api/messages/{recent[0]}/feedback", json={"rating": -1, "reason": "too_long"}, headers=H).json()
r1 = cli.post(f"/api/messages/{recent[1]}/feedback", json={"rating": -1, "reason": "too_long"}, headers=H).json()
r2 = cli.post(f"/api/messages/{recent[2]}/feedback", json={"rating": -1, "reason": "too_long"}, headers=H).json()
prop = r2.get("style_trace") or {}
result = (prop.get("result") or {})
mem_id = result.get("memory_id")
row = q("SELECT status, type, scope, source, content FROM memories WHERE id=?", mem_id)[0] if mem_id else {}
aud = " ".join(r["detail"] or "" for r in q("SELECT detail FROM audit_log WHERE user_id=? AND kind='memory_proposed'", UID))
check("MEM-46", "14 天内 3 次 too_long 才提议 style，且保持 proposed；审计无正文",
      r0.get("style_trace") is None and r1.get("style_trace") is None
      and prop.get("name") == "remember" and result.get("status") == "proposed" and result.get("type") == "style"
      and row.get("status") == "proposed" and row.get("scope") == "bot" and row.get("source") == "feedback"
      and row.get("type") == "style" and config.MEMORY_STYLE_SHORTER not in aud,
      f"row={ {k: row.get(k) for k in ('status', 'type', 'scope', 'source')} }")

confirmed = cli.post(f"/api/memories/{mem_id}/confirm", headers=H)
active = q("SELECT status FROM memories WHERE id=?", mem_id)[0]
profile = cli.post("/api/memories", json={"content": "用户在杭州做产品", "type": "profile", "scope": "global"}, headers=H)
block = memory.recall(UID, db.get_bot(UID, P["id"]), "随便聊聊").block
lines = [ln for ln in block.splitlines() if ln.startswith("- [M")]
check("MEM-48", "确认后的 style 注入在记忆块最前，标签含「风格」",
      confirmed.status_code == 200 and active["status"] == "active" and profile.status_code in (200, 201)
      and lines and "风格" in lines[0] and any("资料" in ln for ln in lines[1:]),
      lines[0][:40] if lines else "")

# 规则命中：本轮回复后追加风格卡片，不自动生效
E = bot("规则Bot")
evs = sse(E["id"], "再短一点")
tr = [d for e, d in evs if e == "tool_result" and d.get("name") == "remember"]
st = (tr[0].get("result") or {}) if tr else {}
stored = q("SELECT status, type, source FROM memories WHERE id=?", st.get("memory_id")) if st.get("memory_id") else []
queued = q("SELECT kind, status FROM memory_jobs WHERE bot_id=? AND kind='summarize'", E["id"])
check("MEM-47", "「再短一点」在回复后追加 style 提议卡片，并入队 summarize",
      len(tr) == 1 and st.get("status") == "proposed" and st.get("type") == "style" and st.get("scope") == "bot"
      and stored == [{"status": "proposed", "type": "style", "source": "feedback"}] and len(queued) == 1,
      f"trace={st.get('status')} stored={stored} jobs={queued}")

# 详细一点是另一条提议，不和「再短一点」混成已生效
evs2 = sse(E["id"], "请详细一点")
tr2 = [d for e, d in evs2 if e == "tool_result" and d.get("name") == "remember"]
st2 = (tr2[0].get("result") or {}) if tr2 else {}
check("MEM-49", "「详细一点」另起一条 proposed，不自动生效",
      st2.get("status") == "proposed" and st2.get("content") == "回答再详细一点" and st2.get("memory_id") != st.get("memory_id")
      and q("SELECT status FROM memories WHERE id=?", st2.get("memory_id")) == [{"status": "proposed"}],
      str(st2.get("status")))

# 日志里不应出现摘要正文或风格正文
blob = LOGBUF.getvalue()
check("MEM-49b", "日志不写摘要正文和风格提议正文",
      "甲乙丙丁摘要" not in blob and config.MEMORY_STYLE_SHORTER not in blob and "回答再详细一点" not in blob)

p = sum(1 for r in RESULTS if r[2])
print(f"\nSUMMARY {p}/{len(RESULTS)} passed")
sys.exit(0 if p == len(RESULTS) else 1)
