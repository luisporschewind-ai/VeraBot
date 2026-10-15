#!/usr/bin/env python3
"""过时的失败 / 中断任务不再充当会话状态；工具 trace 落库瘦身（schema v33）。

临时 SQLite，不调用真实模型。运行（在 backend/ 下）：
    .venv/bin/python scripts/test/stale_work_trace_slim_test.py
"""
from __future__ import annotations

import asyncio
import glob
import json
import os
import sqlite3
import sys
import tempfile
from copy import deepcopy
from pathlib import Path
from unittest.mock import patch

TMP = tempfile.mkdtemp(prefix="vb_stale_slim_")
DB = str(Path(TMP) / "t.db")
os.environ["VERABOT_DB"] = DB
os.environ["VERABOT_DATA_DIR"] = TMP
os.environ["VERABOT_MEMORY_JOBS"] = "0"
os.environ.setdefault("DEEPSEEK_API_KEY", "test-not-used")

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from verabot import db  # noqa: E402
from verabot.agents import runtime  # noqa: E402
from verabot.core import trace_slim  # noqa: E402
from verabot.db import chat_reply_store as chat_store  # noqa: E402
from verabot.db import conversation_activity_store as activity  # noqa: E402

RESULTS = []


def check(cid, name, ok, note=""):
    RESULTS.append((cid, name, bool(ok), note))
    print(f"[{'PASS' if ok else 'FAIL'}] {cid} {name} {note}", flush=True)


FILE_TEXT = "甲" * 30000
READ_FILE = {"filename": "方案.md", "offset": 0, "text": FILE_TEXT, "next_offset": 30000, "has_more": True,
             "text_chars": 52000, "text_status": "ok"}
MCP_CONTENT = "<untrusted_tool_result>" + "x" * 8000 + "</untrusted_tool_result>"
MCP_RESULT = {"content": MCP_CONTENT, "code": None, "is_error": False, "truncated": False}
TRACES = [
    {"id": "rf1", "name": "read_file", "args": {"attachment_id": "att_1"}, "result": READ_FILE},
    {"id": "mcp1", "name": "mcp__learn__search", "args": {"q": "a"}, "result": MCP_RESULT},
    {"id": "ask1", "name": "ask_bot", "args": {"bot_name": "小研"}, "result": {"answer": "短回答", "delegation_id": 7}},
]


def is_slim_read_file(result):
    return ("text" not in result and result.get("filename") == "方案.md" and result.get("offset") == 0
            and result.get("length") == 30000 and result.get("text_chars") == 52000
            and result.get("has_more") is True and result.get("next_offset") == 30000 and result.get("text_omitted") is True)


def is_slim_mcp(result):
    content = result.get("content") or ""
    return (len(content) == trace_slim.TEXT_LIMIT + len(trace_slim.TRUNCATED_MARK)
            and content.endswith(trace_slim.TRUNCATED_MARK)
            and result.get("trace_truncated") == {"content": len(MCP_CONTENT)})


# ---------------------------------------------------------------- 基础数据
db.init_db()
db.init_db()
with db.tx() as c:
    UID = c.execute("INSERT INTO users(username,password_hash,created_at) VALUES ('s','x','now')").lastrowid
    BID, BID_MIG_A, BID_MIG_B, BID_LOOP, BID_LEGACY = [
        c.execute("INSERT INTO bots(user_id,name,created_at) VALUES (?,?,'now')", (UID, name)).lastrowid
        for name in ("主", "迁移A", "迁移B", "循环", "旧版")]
    for bid in (BID, BID_MIG_A, BID_MIG_B, BID_LOOP, BID_LEGACY):
        c.execute("INSERT OR IGNORE INTO conversation_activity VALUES(?,'private',?,1)", (UID, bid))

con = sqlite3.connect(DB)
ver = con.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()[0]
cols = {r[1] for r in con.execute("PRAGMA table_info(chat_reply_tasks)")} & {r[1] for r in con.execute("PRAGMA table_info(owned_tasks)")}
triggers = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'supersede%'")}
con.close()
check("STALE-01", "schema v33：superseded_at 列与触发器，init 幂等",
      ver == "33" and db.SCHEMA_VERSION == 33 and "superseded_at" in cols and len(triggers) == 5,
      f"ver={ver} triggers={sorted(triggers)}")


def accept(bid, key, message="问题"):
    with db.tx(immediate=True) as c:
        response, _ = chat_store.accept(c, UID, bid, {"client_request_id": key, "message": message, "expected_generation": 1})
    return response


def run_task(state, text="回复", traces=None):
    with db.tx(immediate=True) as c:
        task = chat_store.claim_next(c, "w")
        assert task and chat_store.finish(c, task, state, text, traces or [])
    return task


def summary(bid):
    with db.tx() as c:
        return activity.summary(c, UID, "private", bid)


def task_row(tid):
    with db.tx() as c:
        return dict(c.execute("SELECT * FROM chat_reply_tasks WHERE id=?", (tid,)).fetchone())


def message_count(bid):
    with db.tx() as c:
        return c.execute("SELECT COUNT(*) FROM messages WHERE bot_id=?", (bid,)).fetchone()[0]


# ---------------------------------------------------------------- 1. 过时的失败 / 中断任务
first = accept(BID, "one")
with db.tx(immediate=True) as c:
    t1 = chat_store.claim_next(c, "w")
    chat_store.save_partial(c, t1, "一半", [])
    c.execute("UPDATE chat_reply_tasks SET lease_expires_at='2000-01-01' WHERE id=?", (t1["id"],))
    chat_store.recover(c)
s = summary(BID)
check("STALE-02", "最新一轮被中断时照常上报 interrupted",
      s["state"] == "interrupted" and [w["id"] for w in s["work_items"]] == [t1["id"]], f"state={s['state']}")

accept(BID, "two")
t2 = run_task("completed", "正常回复")
s = summary(BID)
row1 = task_row(t1["id"])
with db.tx() as c:
    kept = c.execute("SELECT content,message_status FROM messages WHERE id=?", (first["assistant_message_id"],)).fetchone()
check("STALE-03", "之后有正常完成的回复：旧 interrupted 不再出现在 work_items，状态为 idle",
      s["state"] == "idle" and s["work_items"] == [] and row1["superseded_at"] and row1["state"] == "interrupted",
      f"state={s['state']} work={s['work_items']} superseded_at={row1['superseded_at']}")
check("STALE-04", "标记不删消息：旧回复正文与状态保留",
      message_count(BID) == 4 and kept and "一半" in kept["content"] and kept["message_status"] == "interrupted",
      f"count={message_count(BID)}")

accept(BID, "three")
t3 = run_task("failed", "回复暂时无法完成")
s = summary(BID)
check("STALE-05", "完成之后真正最新的一次失败仍上报 failed",
      s["state"] == "failed" and [w["id"] for w in s["work_items"]] == [t3["id"]] and not task_row(t3["id"])["superseded_at"],
      f"state={s['state']} work={[w['id'] for w in s['work_items']]}")

now = db.now_iso()
with db.tx() as c:
    owned = c.execute("""INSERT INTO owned_tasks(user_id,owner_bot_id,owner_name,goal,completion_criteria,state,authorization_json,
        created_at,updated_at,request_key,request_hash,delivery_generation) VALUES (?,?,'主','g','c','failed','{}',?,?,'ok1','h',1)""",
                      (UID, BID, now, now)).lastrowid
    c.execute("""INSERT INTO messages(user_id,bot_id,role,content,created_at,source_kind,source_id,conversation_generation)
        VALUES (?,?,'assistant','主动任务失败说明',?,'owned_task','1',1)""", (UID, BID, now))
s = summary(BID)
check("STALE-06", "主动任务自己的投递消息不会把它的失败标成过时",
      {(w["source"], w["id"]) for w in s["work_items"]} == {("chat", t3["id"]), ("owned", owned)}, f"work={s['work_items']}")

db.add_message(UID, BID, "assistant", "旧版流式完成的回复")
s = summary(BID)
with db.tx() as c:
    owned_sup = c.execute("SELECT superseded_at FROM owned_tasks WHERE id=?", (owned,)).fetchone()[0]
check("STALE-07", "旧版路径写入的完成回复同样让此前的失败（含主动任务）过时",
      s["state"] == "idle" and s["work_items"] == [] and owned_sup, f"state={s['state']}")

with db.tx() as c:
    c.execute("UPDATE owned_tasks SET state='queued' WHERE id=?", (owned,))
    reopened = c.execute("SELECT superseded_at FROM owned_tasks WHERE id=?", (owned,)).fetchone()[0]
    c.execute("UPDATE owned_tasks SET state='failed' WHERE id=?", (owned,))
s = summary(BID)
check("STALE-08", "任务重新进入非终态时清除标记，再次失败照常上报",
      reopened is None and [w["id"] for w in s["work_items"] if w["source"] == "owned"] == [owned], f"state={s['state']}")


# ---------------------------------------------------------------- 2. 持久化瘦身
accept(BID, "four")
with db.tx(immediate=True) as c:
    t4 = chat_store.claim_next(c, "w")
    chat_store.save_partial(c, t4, "读取中", deepcopy(TRACES[:1]))
    chat_store.event(c, t4, "tool_result", deepcopy(TRACES[0]))
    chat_store.finish(c, t4, "completed", "读完了", deepcopy(TRACES))
with db.tx() as c:
    stored = json.loads(c.execute("SELECT traces FROM messages WHERE id=?", (t4["output_message_id"],)).fetchone()[0])
    events = [(r["event"], json.loads(r["payload_json"])) for r in
              c.execute("SELECT event,payload_json FROM chat_reply_events WHERE task_id=? ORDER BY id", (t4["id"],))]
check("TRACE-01", "finish 落库：read_file 去原文留元数据，MCP 长字段截到 2000 字带标记，其他字段不动",
      is_slim_read_file(stored[0]["result"]) and is_slim_mcp(stored[1]["result"])
      and stored[2] == TRACES[2] and stored[0]["args"] == TRACES[0]["args"],
      f"read_file={ {k: v for k, v in stored[0]['result'].items()} }")
partial = next(p for e, p in events if e == "message_updated")
tool_event = next(p for e, p in events if e == "tool_result")
final = [p for e, p in events if e == "task_updated"][-1]
check("TRACE-02", "回复事件（message_updated / tool_result / task_updated）同步的也是瘦身后的 trace",
      is_slim_read_file(partial["traces"][0]["result"]) and is_slim_read_file(tool_event["result"])
      and is_slim_read_file(final["task"]["traces"][0]["result"]) and FILE_TEXT[:100] not in json.dumps(events, ensure_ascii=False),
      f"events={[e for e, _ in events]}")

mid = db.add_message(UID, BID, "assistant", "旧版", deepcopy(TRACES))
with db.tx() as c:
    legacy = json.loads(c.execute("SELECT traces FROM messages WHERE id=?", (mid,)).fetchone()[0])
again = trace_slim.slim_traces(deepcopy(legacy))
check("TRACE-03", "add_message 同样瘦身；再次瘦身结果不变",
      is_slim_read_file(legacy[0]["result"]) and is_slim_mcp(legacy[1]["result"]) and again == legacy)
error_trace = {"id": "e", "name": "read_file", "args": {}, "result": {"error": "文件未授权给当前对话", "code": "attachment_not_found"}}
check("TRACE-04", "read_file 错误结果与短结果原样保留",
      trace_slim.slim_trace(error_trace) == error_trace
      and trace_slim.slim_trace(TRACES[2]) == TRACES[2])


# ---------------------------------------------------------------- 3. 模型仍拿到完整结果
LOOP_TEXT = "乙" * 5000
LOOP_RESULT = {"filename": "方案.md", "offset": 0, "text": LOOP_TEXT, "next_offset": 5000, "has_more": True,
               "text_chars": 52000, "text_status": "ok"}


async def fake_dispatch(ctx, name, arguments, call_id=None):
    return deepcopy(LOOP_RESULT)


def make_model(prompts):
    async def model(messages, *args, **kwargs):
        prompts.append(deepcopy(messages))
        if not any(m.get("role") == "tool" for m in messages):
            yield "tool_calls", [{"id": "rf-loop", "name": "read_file", "arguments": '{"attachment_id":"att_x"}'}]
        else:
            yield "delta", "读完了"
        yield "usage", {"total_tokens": 3}
    return model


def tool_message(prompts):
    return next((m for p in prompts for m in p if m.get("role") == "tool" and m.get("tool_call_id") == "rf-loop"), None)


from verabot.services.chat_tasks import worker  # noqa: E402

prompts: list = []
loop_task = accept(BID_LOOP, "loop")
with patch("verabot.services.llm.stream_chat", make_model(prompts)), patch("verabot.agents.runtime.dispatch", fake_dispatch):
    asyncio.run(worker.process_one("fixture"))
tool_msg = tool_message(prompts)
with db.tx() as c:
    loop_traces = json.loads(c.execute("SELECT traces FROM messages WHERE id=?", (loop_task["assistant_message_id"],)).fetchone()[0])
    loop_events = [json.loads(r[0]) for r in c.execute(
        "SELECT payload_json FROM chat_reply_events WHERE task_id=? AND event='tool_result'", (loop_task["task"]["id"],))]
    loop_state = c.execute("SELECT state FROM chat_reply_tasks WHERE id=?", (loop_task["task"]["id"],)).fetchone()[0]
check("LOOP-01", "持久回复：模型下一轮拿到完整 read_file 结果（含 5000 字正文）",
      loop_state == "completed" and tool_msg is not None
      and tool_msg["content"] == runtime._tool_content("read_file", LOOP_RESULT) and LOOP_TEXT in tool_msg["content"],
      f"state={loop_state} tool_len={len(tool_msg['content']) if tool_msg else None}")
check("LOOP-02", "持久回复：落库 trace 与 tool_result 事件不含正文",
      "text" not in loop_traces[0]["result"] and loop_traces[0]["result"]["length"] == 5000
      and loop_events and all("text" not in e["result"] for e in loop_events))

prompts = []
bot = db.get_bot(UID, BID_LEGACY)


async def legacy_run():
    return [ev async for ev in runtime.run_chat(UID, bot, "读文件")]


with patch("verabot.services.llm.stream_chat", make_model(prompts)), patch("verabot.agents.runtime.dispatch", fake_dispatch):
    sse = asyncio.run(legacy_run())
tool_msg = tool_message(prompts)
sse_trace = next(ev["data"] for ev in sse if ev["event"] == "tool_result")
with db.tx() as c:
    legacy_traces = json.loads(c.execute(
        "SELECT traces FROM messages WHERE bot_id=? AND role='assistant' ORDER BY id DESC LIMIT 1", (BID_LEGACY,)).fetchone()[0])
check("LOOP-03", "旧版流式：模型拿到完整结果；SSE 与落库的 trace 已瘦身",
      tool_msg is not None and LOOP_TEXT in tool_msg["content"]
      and "text" not in sse_trace["result"] and "text" not in legacy_traces[0]["result"]
      and legacy_traces[0]["result"]["length"] == 5000)


# ---------------------------------------------------------------- 4. 迁移：存量夹具
OLD = "2026-10-01T00:00:00+00:00"
LATER = "2026-10-02T00:00:00+00:00"
raw = sqlite3.connect(DB)
for name in ("supersede_stale_work_reply_insert", "supersede_stale_work_reply_update", "supersede_stale_work_owned_completed",
             "superseded_chat_task_reopened", "superseded_owned_task_reopened"):
    raw.execute(f"DROP TRIGGER IF EXISTS {name}")


def fixture_message(bid, role, status, created, content="m", traces=None, source_kind=None):
    return raw.execute("""INSERT INTO messages(user_id,bot_id,role,content,traces,created_at,message_status,conversation_generation,source_kind)
        VALUES (?,?,?,?,?,?,?,1,?)""", (UID, bid, role, content, json.dumps(traces, ensure_ascii=False) if traces else None,
                                         created, status, source_kind)).lastrowid


def fixture_task(bid, key, inp, out, state, updated):
    return raw.execute("""INSERT INTO chat_reply_tasks(user_id,bot_id,generation,client_request_id,payload_hash,input_message_id,
        output_message_id,state,phase,created_at,updated_at) VALUES (?,?,1,?,'h',?,?,?,?,?,?)""",
                       (UID, bid, key, inp, out, state, state, OLD, updated)).lastrowid


def fixture_owned(bid, key, state, updated):
    return raw.execute("""INSERT INTO owned_tasks(user_id,owner_bot_id,owner_name,goal,completion_criteria,state,authorization_json,
        created_at,updated_at,request_key,request_hash,delivery_generation) VALUES (?,?,'b','g','c',?,'{}',?,?,?,'h',1)""",
                       (UID, bid, state, OLD, updated, key)).lastrowid


# 会话 A：中断 → 之后正常完成回复（带大 trace）→ 旧任务与旧主动失败都应过时
a_in = fixture_message(BID_MIG_A, "user", "completed", OLD)
a_out = fixture_message(BID_MIG_A, "assistant", "interrupted", OLD, "回复因服务中断而停止")
stale_a = fixture_task(BID_MIG_A, "a1", a_in, a_out, "interrupted", OLD)
stale_owned = fixture_owned(BID_MIG_A, "oa", "failed", OLD)
fixture_message(BID_MIG_A, "user", "completed", LATER)
big_mid = fixture_message(BID_MIG_A, "assistant", "completed", LATER, "正常回复", deepcopy(TRACES))
big_event = raw.execute("""INSERT INTO chat_reply_events(user_id,bot_id,task_id,generation,version,event,payload_json,created_at)
    VALUES (?,?,?,1,1,'tool_result',?,?)""", (UID, BID_MIG_A, stale_a, json.dumps(TRACES[0], ensure_ascii=False), OLD)).lastrowid
# 会话 B：先完成回复，之后失败 → 失败是真实的最新状态
fixture_message(BID_MIG_B, "assistant", "completed", OLD, "早先的回复")
b_in = fixture_message(BID_MIG_B, "user", "completed", LATER)
b_out = fixture_message(BID_MIG_B, "assistant", "failed", LATER, "回复暂时无法完成")
latest_b = fixture_task(BID_MIG_B, "b1", b_in, b_out, "failed", LATER)
latest_owned = fixture_owned(BID_MIG_B, "ob", "interrupted", "2999-01-01T00:00:00+00:00")
raw.execute("UPDATE schema_meta SET value='32' WHERE key='version'")
raw.commit()
counts_before = raw.execute("SELECT COUNT(*) FROM messages").fetchone()[0]
raw.close()

db.init_db()
con = sqlite3.connect(DB)
con.row_factory = sqlite3.Row
ver = con.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()[0]
flags = {tid: con.execute("SELECT superseded_at FROM chat_reply_tasks WHERE id=?", (tid,)).fetchone()[0] for tid in (stale_a, latest_b)}
owned_flags = {tid: con.execute("SELECT superseded_at FROM owned_tasks WHERE id=?", (tid,)).fetchone()[0] for tid in (stale_owned, latest_owned)}
migrated = json.loads(con.execute("SELECT traces FROM messages WHERE id=?", (big_mid,)).fetchone()[0])
migrated_event = json.loads(con.execute("SELECT payload_json FROM chat_reply_events WHERE id=?", (big_event,)).fetchone()[0])
counts_after = con.execute("SELECT COUNT(*) FROM messages").fetchone()[0]
trigger_count = con.execute("SELECT COUNT(*) FROM sqlite_master WHERE type='trigger' AND name LIKE 'supersede%'").fetchone()[0]
con.close()
backups = glob.glob(DB + ".bak-before-v33-*")
s_a, s_b = summary(BID_MIG_A), summary(BID_MIG_B)
check("MIG-01", "v32 → v33：之后有正常完成回复的中断任务 / 主动失败被标记，会话为 idle",
      ver == "33" and flags[stale_a] and owned_flags[stale_owned] and s_a["state"] == "idle" and s_a["work_items"] == [],
      f"flags={flags} owned={owned_flags} state={s_a['state']}")
check("MIG-02", "v32 → v33：真正最新的失败 / 中断不标记，照常上报",
      not flags[latest_b] and not owned_flags[latest_owned] and s_b["state"] == "failed"
      and {(w["source"], w["id"]) for w in s_b["work_items"]} == {("chat", latest_b), ("owned", latest_owned)},
      f"state={s_b['state']}")
check("MIG-03", "v32 → v33：存量 messages.traces 与回复事件瘦身，消息条数不变，触发器重建，迁移前已备份",
      is_slim_read_file(migrated[0]["result"]) and is_slim_mcp(migrated[1]["result"]) and migrated[2] == TRACES[2]
      and is_slim_read_file(migrated_event["result"]) and counts_before == counts_after and trigger_count == 5 and len(backups) == 1,
      f"messages {counts_before}->{counts_after} backups={len(backups)}")

db.init_db()
con = sqlite3.connect(DB)
again_traces = json.loads(con.execute("SELECT traces FROM messages WHERE id=?", (big_mid,)).fetchone()[0])
again_flag = con.execute("SELECT superseded_at FROM chat_reply_tasks WHERE id=?", (latest_b,)).fetchone()[0]
con.close()
check("MIG-04", "再次 init_db 幂等：不再回填、不重复备份",
      again_traces == migrated and again_flag is None and len(glob.glob(DB + ".bak-before-v33-*")) == 1)

failed = [r for r in RESULTS if not r[2]]
print(f"\n{len(RESULTS) - len(failed)}/{len(RESULTS)} passed", flush=True)
sys.exit(1 if failed else 0)
