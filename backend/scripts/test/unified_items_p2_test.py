#!/usr/bin/env python3
"""统一事项 P2：交给 Bot（创建任务+关联、操作代理、写回同步、propose_task、删除语义、越权）。"""
import asyncio
import json
import os
import sqlite3
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TMP = tempfile.mkdtemp(prefix="vb_items_p2_")
DB = str(Path(TMP) / "t.db")
os.environ["VERABOT_DB"] = DB
os.environ["VERABOT_DATA_DIR"] = TMP
os.environ["VERABOT_SCHEDULER"] = "0"
os.environ.setdefault("DEEPSEEK_API_KEY", "test-not-used")
sys.path.insert(0, str(ROOT))

from verabot import db  # noqa: E402
from verabot.services.reminders import clock  # noqa: E402

db.init_db()

from fastapi.testclient import TestClient  # noqa: E402
from verabot.main import app  # noqa: E402
from verabot.tools.registry import ToolContext, TurnState, run_tool  # noqa: E402

cli = TestClient(app)
NOW = datetime.now(timezone.utc)
clock.set_now(NOW)
SH = __import__("zoneinfo").ZoneInfo("Asia/Shanghai")
TZ = "Asia/Shanghai"
start = (NOW + timedelta(days=30)).astimezone(SH).isoformat(timespec="seconds")


def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat(timespec="seconds")


def conn() -> sqlite3.Connection:
    return sqlite3.connect(DB)


def auth(name: str):
    res = cli.post("/api/auth/register", json={"username": name, "password": "pw123456"})
    assert res.status_code == 200, res.text
    return {"Authorization": "Bearer " + res.json()["token"]}, res.json()


HA, auth_a = auth("p2-a")
HB, auth_b = auth("p2-b")
bot_a = cli.post("/api/bots", json={"name": "甲"}, headers=HA).json()
bot_b = cli.post("/api/bots", json={"name": "乙"}, headers=HA).json()
uid_a = conn().execute("SELECT id FROM users WHERE username='p2-a'").fetchone()[0]

# 开启主 Bot + 主动任务（owned 需要）
pb = cli.patch("/api/primary-bot", json={"primary_bot_id": bot_a["id"], "active_enabled": True,
                                          "expected_version": 1}, headers=HA)
assert pb.status_code == 200, pb.text



# ---------- P2-01：POST /api/items 带 task（once / repeat / owned） + 幂等 ----------
once = cli.post("/api/items", json={
    "title": "到点做一次", "task": {"bot_id": bot_a["id"], "instruction": "做一次", "mode": "once",
                                     "start_at": start, "timezone": TZ}},
    headers={**HA, "Idempotency-Key": "p2-once-1"}).json()
assert once["task_kind"] == "scheduled" and once["task_id"], once
assert once["notify"] is False
assert once["task"]["kind"] == "scheduled" and once["task"]["bot_id"] == bot_a["id"]
sid = once["task_id"]
srow = conn().execute("SELECT repeat, execution_mode FROM scheduled_tasks WHERE id=?", (sid,)).fetchone()
assert srow == ("once", "read_only"), srow

# 同一 Idempotency-Key 重放：同一事项、不重复建任务
once2 = cli.post("/api/items", json={
    "title": "到点做一次", "task": {"bot_id": bot_a["id"], "instruction": "做一次", "mode": "once",
                                     "start_at": start, "timezone": TZ}},
    headers={**HA, "Idempotency-Key": "p2-once-1"}).json()
assert once2["id"] == once["id"]
assert conn().execute("SELECT COUNT(*) FROM scheduled_tasks WHERE id=?", (sid,)).fetchone()[0] == 1

repeat = cli.post("/api/items", json={
    "title": "每天简报", "task": {"bot_id": bot_b["id"], "instruction": "写简报", "mode": "repeat",
                                   "repeat": "daily", "start_at": start, "timezone": TZ}},
    headers={**HA, "Idempotency-Key": "p2-repeat-1"}).json()
assert repeat["task_kind"] == "scheduled" and repeat["notify"] is False
rrow = conn().execute("SELECT repeat FROM scheduled_tasks WHERE id=?", (repeat["task_id"],)).fetchone()
assert rrow == ("daily",), rrow

owned = cli.post("/api/items", json={
    "title": "整理资料", "task": {"bot_id": bot_a["id"], "instruction": "整理", "mode": "owned",
                                   "completion_criteria": "全部归档"}},
    headers={**HA, "Idempotency-Key": "p2-owned-1"}).json()
assert owned["task_kind"] == "owned" and owned["task_id"], owned
assert owned["task"]["kind"] == "owned"
orow = conn().execute("SELECT state FROM owned_tasks WHERE id=?", (owned["task_id"],)).fetchone()
assert orow == ("queued",), orow
print("PASS P2-01 create with task (once/repeat/owned) + idempotency")

# ---------- P2-02：owned 需要主动任务；无权限拒绝 ----------
bot_b2 = cli.post("/api/bots", json={"name": "乙2"}, headers=HB).json()
denied_owned = cli.post("/api/items", json={
    "title": "越权持续", "task": {"bot_id": bot_b2["id"], "instruction": "x", "mode": "owned",
                                   "completion_criteria": "y"}}, headers=HB)
assert denied_owned.status_code == 409, denied_owned.text
print("PASS P2-02 owned requires primary bot + active tasks")

# ---------- P2-03：任务操作代理（scheduled pause/resume/run；不泄露内部字段） ----------
paused = cli.post(f"/api/items/{once['id']}/task/pause", headers=HA).json()
assert paused["task"]["status_key"] == "failed"  # paused 状态映射为「未完成」
assert conn().execute("SELECT state FROM scheduled_tasks WHERE id=?", (sid,)).fetchone()[0] == "paused"
resumed = cli.post(f"/api/items/{once['id']}/task/resume", headers=HA).json()
assert conn().execute("SELECT state FROM scheduled_tasks WHERE id=?", (sid,)).fetchone()[0] == "active"
run = cli.post(f"/api/items/{once['id']}/task/run", headers={**HA, "Idempotency-Key": "p2-run-1"})
assert run.status_code in (200, 202), run.text
blob = json.dumps(paused, ensure_ascii=False)
for forbidden in ("lease_token", "lease_owner", "authorization_json", "trace_summary", "request_hash"):
    assert forbidden not in blob, forbidden
print("PASS P2-03 scheduled op proxy pause/resume/run + no internals")

# ---------- P2-04：owned 操作代理 stop → 解除关联并标注任务已结束 ----------
stopped = cli.post(f"/api/items/{owned['id']}/task/stop", headers=HA).json()
assert stopped.get("task") is None, stopped.get("task")
assert conn().execute("SELECT state FROM owned_tasks WHERE id=?", (owned["task_id"],)).fetchone()[0] == "stopped"
# 停止后事项保留但解除关联
item_row = conn().execute("SELECT task_kind, task_id, status FROM reminders WHERE id=?", (owned["id"],)).fetchone()
assert item_row[0] is None and item_row[1] is None and item_row[2] != "cancelled", item_row
events = conn().execute("SELECT kind FROM reminder_events WHERE reminder_id=?", (owned["id"],)).fetchall()
assert ("task_unlinked",) in events, events
print("PASS P2-04 owned stop unlinks item and annotates")

# ---------- P2-05：owned continue / input ----------
reowned = cli.post("/api/items", json={
    "title": "继续任务", "task": {"bot_id": bot_a["id"], "instruction": "做", "mode": "owned",
                                   "completion_criteria": "完成"}},
    headers={**HA, "Idempotency-Key": "p2-owned-2"}).json()
# 置为 awaiting_user + 一个 wait，测试 input
con = conn()
con.execute("UPDATE owned_tasks SET state='awaiting_user' WHERE id=?", (reowned["task_id"],))
con.execute("""INSERT INTO owned_steps(id,task_id,bot_id,version,kind,status,input_json,action_key,available_at,created_at)
               VALUES (9000,?,?,?, 'owner','completed','{}','k9000',?,?)""",
            (reowned["task_id"], bot_a["id"], 1, iso(NOW), iso(NOW)))
con.execute("""INSERT INTO owned_waits(task_id,step_id,version,kind,question)
               VALUES (?,9000,1,'await_user','要补充什么？')""", (reowned["task_id"],))
con.commit()
answered = cli.post(f"/api/items/{reowned['id']}/task/input", json={"message": "补充好了"},
                    headers={**HA, "Idempotency-Key": "p2-input-1"}).json()
assert answered.get("task") is not None, answered
assert conn().execute("SELECT state FROM owned_tasks WHERE id=?", (reowned["task_id"],)).fetchone()[0] == "queued"
# 置为 failed → continue
con = conn()
con.execute("UPDATE owned_tasks SET state='failed' WHERE id=?", (reowned["task_id"],))
con.commit()
cont = cli.post(f"/api/items/{reowned['id']}/task/continue", headers=HA).json()
assert conn().execute("SELECT state FROM owned_tasks WHERE id=?", (reowned["task_id"],)).fetchone()[0] == "queued"
print("PASS P2-05 owned continue + input proxy")

# ---------- P2-06：写回同步（owned 完成 → 事项自动完成；scheduled 推进 → 事项下次时间） ----------
from verabot.services.items import sync as item_sync  # noqa: E402
from verabot.db import item_store  # noqa: E402

own2 = cli.post("/api/items", json={
    "title": "会自动完成", "task": {"bot_id": bot_a["id"], "instruction": "做", "mode": "owned",
                                     "completion_criteria": "完成"}},
    headers={**HA, "Idempotency-Key": "p2-owned-3"}).json()
con = conn()
con.execute("UPDATE owned_tasks SET state='completed' WHERE id=?", (own2["task_id"],))
con.commit()
item_sync.on_owned_completed(uid_a, own2["task_id"])
assert conn().execute("SELECT status FROM reminders WHERE id=?", (own2["id"],)).fetchone()[0] == "done"

sched2 = cli.post("/api/items", json={
    "title": "周期推进", "task": {"bot_id": bot_a["id"], "instruction": "做", "mode": "repeat",
                                   "repeat": "daily", "start_at": start, "timezone": TZ}},
    headers={**HA, "Idempotency-Key": "p2-repeat-2"}).json()
nxt = iso(NOW + timedelta(days=31))
con = conn()
con.execute("UPDATE scheduled_tasks SET next_run_at_utc=? WHERE id=?", (nxt, sched2["task_id"]))
con.commit()
with db.tx() as c:
    item_sync.on_scheduled_advanced(c, uid_a, sched2["task_id"])
due_utc = conn().execute("SELECT due_utc FROM reminders WHERE id=?", (sched2["id"],)).fetchone()[0]
assert due_utc is not None and due_utc.startswith("2026") or due_utc.startswith("2027"), due_utc
print("PASS P2-06 write-back sync (owned complete + scheduled advance)")

# ---------- P2-07：propose_task 确认卡片 → 确认后创建任务+事项 ----------
cli.patch(f"/api/bots/{bot_a['id']}",
          json={"allowed_tools": ["create_reminder", "list_reminders", "manage_reminder", "propose_task"]},
          headers=HA)
full_a = cli.get(f"/api/bots/{bot_a['id']}", headers=HA).json()
ctx = ToolContext(user_id=uid_a, bot=full_a, turn=TurnState(), user_text="帮我每天整理")


def tool(name, args, context=None):
    return asyncio.run(run_tool(context or ctx, name, json.dumps(args)))


proposed = tool("propose_task", {"title": "每日整理", "mode": "repeat", "repeat": "daily",
                                  "start_at": start, "timezone": TZ})
assert proposed.get("status") == "pending_confirmation" and proposed.get("action_id"), proposed
aid = proposed["action_id"]
assert conn().execute("SELECT kind FROM pending_actions WHERE id=?", (aid,)).fetchone()[0] == "propose_task"
confirmed = cli.post(f"/api/pending-actions/{aid}/confirm", headers=HA)
assert confirmed.status_code == 200, confirmed.text
assert confirmed.json()["status"] == "done"
new_item = confirmed.json()["execution"]["item_id"]
detail = cli.get(f"/api/items/{new_item}", headers=HA).json()
assert detail["task_kind"] == "scheduled" and detail["source_kind"] == "chat"
assert detail["created_by"] == "bot"
print("PASS P2-07 propose_task card + confirm creates task/item")

# ---------- P2-08：删除语义（删除并停止 Bot 任务；仅删除事项 keep） ----------
del_item = cli.post("/api/items", json={
    "title": "会被删除", "task": {"bot_id": bot_a["id"], "instruction": "做", "mode": "repeat",
                                   "repeat": "daily", "start_at": start, "timezone": TZ}},
    headers={**HA, "Idempotency-Key": "p2-del-1"}).json()
del_tid = del_item["task_id"]
assert cli.delete(f"/api/items/{del_item['id']}?task=stop", headers=HA).status_code == 200
assert conn().execute("SELECT state FROM scheduled_tasks WHERE id=?", (del_tid,)).fetchone()[0] == "deleted"
assert conn().execute("SELECT status FROM reminders WHERE id=?", (del_item["id"],)).fetchone()[0] == "cancelled"

keep_item = cli.post("/api/items", json={
    "title": "只删事项", "task": {"bot_id": bot_a["id"], "instruction": "做", "mode": "repeat",
                                   "repeat": "daily", "start_at": start, "timezone": TZ}},
    headers={**HA, "Idempotency-Key": "p2-del-2"}).json()
keep_tid = keep_item["task_id"]
assert cli.delete(f"/api/items/{keep_item['id']}?task=keep", headers=HA).status_code == 200
assert conn().execute("SELECT state FROM scheduled_tasks WHERE id=?", (keep_tid,)).fetchone()[0] == "active"
print("PASS P2-08 delete item with task=stop/keep")

# ---------- P2-09：§5.2 越权 + 旧接口 complete 只完成事项 ----------
other = cli.post("/api/items", json={"title": "别人的"}, headers=HB).json()
denied = tool("manage_reminder", {"action": "complete", "id": other["id"]})
assert denied.get("error") == "提醒不存在", denied
linked_item = cli.get("/api/items", params={"view": "bot"}, headers=HA).json()["items"][0]
old_state = conn().execute("SELECT state FROM owned_tasks WHERE id=?", (reowned["task_id"],)).fetchone()[0]
cli.post(f"/api/reminders/{linked_item['id']}/complete", headers=HA).raise_for_status()
new_state = conn().execute("SELECT state FROM owned_tasks WHERE id=?", (reowned["task_id"],)).fetchone()[0]
assert old_state == new_state
print("PASS P2-09 §5.2 scope + legacy complete only completes item")

# ---------- P2-10：SQL 分层 ----------
import importlib.util
spec = importlib.util.spec_from_file_location("sql_layer_check", ROOT / "scripts/test/sql_layer_check.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
assert mod.main() == 0
print("PASS P2-10 sql_layer_check")
print("ALL unified_items_p2_test PASSED")
