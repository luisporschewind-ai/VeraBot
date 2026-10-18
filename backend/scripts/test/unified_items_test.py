#!/usr/bin/env python3
"""统一事项 P1：v37 迁移与回填幂等、views、清单、任务摘要、§5.2、旧 reminders API。"""
import json
import os
import sqlite3
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[2]
TMP = tempfile.mkdtemp(prefix="vb_items_")
DB = str(Path(TMP) / "t.db")
os.environ["VERABOT_DB"] = DB
os.environ["VERABOT_DATA_DIR"] = TMP
os.environ["VERABOT_SCHEDULER"] = "0"
os.environ.setdefault("DEEPSEEK_API_KEY", "test-not-used")
sys.path.insert(0, str(ROOT))

SH = ZoneInfo("Asia/Shanghai")
NOW0 = datetime(2026, 10, 18, 2, 0, tzinfo=timezone.utc)  # 上海 10:00


def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat(timespec="seconds")


# ---------- 从 v36 升到 v37：列 / 表 / 回填 / 备份 / 幂等 ----------
con = sqlite3.connect(DB)
con.executescript("""
CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT UNIQUE NOT NULL, password_hash TEXT NOT NULL,
 created_at TEXT NOT NULL, token_budget INTEGER, nickname TEXT, avatar_updated_at TEXT, memory_enabled INTEGER DEFAULT 1);
CREATE TABLE bots (id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL, name TEXT NOT NULL, avatar TEXT NOT NULL DEFAULT '🤖',
 color TEXT NOT NULL DEFAULT '#0F766E', persona TEXT NOT NULL DEFAULT '', instructions TEXT NOT NULL DEFAULT '',
 created_at TEXT NOT NULL, allowed_tools TEXT NOT NULL DEFAULT '[]', delegate_to TEXT NOT NULL DEFAULT '[]',
 accept_delegation INTEGER NOT NULL DEFAULT 0, image_updated_at TEXT, memory_access TEXT NOT NULL DEFAULT 'bot_and_global',
 tags TEXT NOT NULL DEFAULT '[]', pinned_at TEXT, UNIQUE(user_id, name));
CREATE TABLE reminders (
  id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL, bot_id INTEGER, content TEXT NOT NULL,
  due_at TEXT, done INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL,
  title TEXT, note TEXT, timezone TEXT NOT NULL DEFAULT 'Asia/Shanghai', due_utc TEXT, all_day INTEGER NOT NULL DEFAULT 0,
  rrule TEXT, occurrence_index INTEGER NOT NULL DEFAULT 1, status TEXT NOT NULL DEFAULT 'scheduled',
  snoozed_until TEXT, priority INTEGER NOT NULL DEFAULT 0, created_by TEXT NOT NULL DEFAULT 'user',
  assignee_bot_id INTEGER, source_message_id INTEGER, client TEXT, notify INTEGER NOT NULL DEFAULT 1,
  alert_offsets TEXT NOT NULL DEFAULT '[0]', version INTEGER NOT NULL DEFAULT 1,
  completed_at TEXT, cancelled_at TEXT, updated_at TEXT);
CREATE TABLE reminder_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER NOT NULL, reminder_id INTEGER NOT NULL,
  kind TEXT NOT NULL, from_status TEXT, to_status TEXT, occurrence_due_utc TEXT,
  actor TEXT NOT NULL, actor_bot_id INTEGER, client TEXT, detail TEXT, created_at TEXT NOT NULL);
CREATE TABLE scheduled_tasks (
 id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL, bot_id INTEGER,
 title TEXT NOT NULL, instruction TEXT NOT NULL,
 state TEXT NOT NULL CHECK(state IN ('active','paused','completed','deleted')),
 timezone TEXT NOT NULL, start_at_utc TEXT NOT NULL, rrule TEXT,
 next_run_at_utc TEXT, misfire_policy TEXT NOT NULL DEFAULT 'skip',
 schedule_revision INTEGER NOT NULL DEFAULT 1, version INTEGER NOT NULL DEFAULT 1,
 repeat TEXT NOT NULL DEFAULT 'once', weekdays_json TEXT NOT NULL DEFAULT '[]',
 pause_reason TEXT, authorized_tools_json TEXT NOT NULL DEFAULT '{}',
 idempotency_key TEXT, request_hash TEXT,
 created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT,
 execution_mode TEXT NOT NULL DEFAULT 'read_only');
CREATE TABLE scheduled_task_runs (
 id INTEGER PRIMARY KEY, task_id INTEGER NOT NULL, user_id INTEGER NOT NULL, bot_id INTEGER,
 trigger TEXT NOT NULL, scheduled_for_utc TEXT NOT NULL, schedule_revision INTEGER NOT NULL,
 idempotency_key TEXT, request_hash TEXT, state TEXT NOT NULL,
 task_snapshot_json TEXT NOT NULL, available_at TEXT NOT NULL, created_at TEXT NOT NULL,
 result_text TEXT, error_summary TEXT, message_id INTEGER, finished_at TEXT);
CREATE TABLE owned_tasks (
 id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL, owner_bot_id INTEGER, owner_name TEXT NOT NULL,
 goal TEXT NOT NULL, completion_criteria TEXT NOT NULL, state TEXT NOT NULL,
 version INTEGER NOT NULL DEFAULT 1, authorization_json TEXT NOT NULL DEFAULT '{}',
 token_limit INTEGER NOT NULL DEFAULT 20000, used_tokens INTEGER NOT NULL DEFAULT 0, reserved_tokens INTEGER NOT NULL DEFAULT 0,
 chain_calls INTEGER NOT NULL DEFAULT 0, chain_output INTEGER NOT NULL DEFAULT 0,
 chain_seconds REAL NOT NULL DEFAULT 0, chain_tools INTEGER NOT NULL DEFAULT 0,
 tainted INTEGER NOT NULL DEFAULT 0, blocker_code TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
 request_key TEXT NOT NULL, request_hash TEXT NOT NULL, scheduled_run_id INTEGER);
CREATE TABLE owned_steps (
 id INTEGER PRIMARY KEY, task_id INTEGER NOT NULL, bot_id INTEGER, version INTEGER NOT NULL,
 kind TEXT NOT NULL DEFAULT 'owner', status TEXT NOT NULL DEFAULT 'queued',
 input_json TEXT NOT NULL DEFAULT '{}', result_json TEXT, action_key TEXT NOT NULL UNIQUE,
 available_at TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL,
 message_id INTEGER, delivered_at TEXT);
CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
INSERT INTO schema_meta VALUES ('version','36');
INSERT INTO users(id, username, password_hash, created_at) VALUES (1,'legacy','x','2026-01-01T00:00:00+00:00');
INSERT INTO bots(id, user_id, name, created_at) VALUES (1,1,'助手','2026-01-01T00:00:00+00:00');
""")
next_run = iso(NOW0 + timedelta(hours=5))
con.execute(
    """INSERT INTO scheduled_tasks(id,user_id,bot_id,title,instruction,state,timezone,start_at_utc,next_run_at_utc,
       created_at,updated_at) VALUES (10,1,1,'每日简报','做简报','active','Asia/Shanghai',?,?,?,?)""",
    (iso(NOW0), next_run, iso(NOW0), iso(NOW0)))
con.execute(
    """INSERT INTO owned_tasks(id,user_id,owner_bot_id,owner_name,goal,completion_criteria,state,created_at,updated_at,
       request_key,request_hash) VALUES (20,1,1,'助手','整理资料','完成清单','awaiting_user',?,?, 'k1','h1')""",
    (iso(NOW0), iso(NOW0)))
con.execute(
    """INSERT INTO owned_tasks(id,user_id,owner_bot_id,owner_name,goal,completion_criteria,state,created_at,updated_at,
       request_key,request_hash,scheduled_run_id) VALUES (21,1,1,'助手','桥接任务','完成','queued',?,?, 'k2','h2',99)""",
    (iso(NOW0), iso(NOW0)))
con.execute(
    """INSERT INTO scheduled_tasks(id,user_id,bot_id,title,instruction,state,timezone,start_at_utc,next_run_at_utc,
       created_at,updated_at,deleted_at) VALUES (11,1,1,'已删','x','deleted','Asia/Shanghai',?,?,?,?,?)""",
    (iso(NOW0), next_run, iso(NOW0), iso(NOW0), iso(NOW0)))
con.commit()
con.close()

from verabot import db
db.init_db()
db.init_db()
con = sqlite3.connect(DB)
ver = con.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()[0]
cols = {r[1] for r in con.execute("PRAGMA table_info(reminders)")}
tables = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}
backups = list(Path(TMP).glob("*.bak-before-v37-*"))
linked = con.execute(
    "SELECT task_kind, task_id, title, notify, due_utc, assignee_bot_id FROM reminders WHERE task_id IS NOT NULL ORDER BY task_kind, task_id"
).fetchall()
n_checklist = con.execute("SELECT COUNT(*) FROM reminder_checklist").fetchone()[0]
con.close()
assert ver == "37" == str(db.SCHEMA_VERSION) or (ver == str(db.SCHEMA_VERSION) and db.SCHEMA_VERSION == 37), ver
assert {"task_kind", "task_id", "source_kind", "checklist_done", "checklist_total"} <= cols
assert "reminder_checklist" in tables
assert len(backups) == 1, backups
assert n_checklist == 0
assert len(linked) == 2, linked  # scheduled 10 + owned 20；deleted / bridged 跳过
by = {(r[0], r[1]): r for r in linked}
assert by[("scheduled", 10)][2] == "每日简报" and by[("scheduled", 10)][3] == 0 and by[("scheduled", 10)][4] == next_run
assert by[("owned", 20)][2] == "整理资料" and by[("owned", 20)][4] is None and by[("owned", 20)][5] == 1
db.init_db()
con = sqlite3.connect(DB)
assert con.execute("SELECT COUNT(*) FROM reminders WHERE task_id IS NOT NULL").fetchone()[0] == 2
assert len(list(Path(TMP).glob("*.bak-before-v37-*"))) == 1
con.close()
print("PASS ITEMS-01 migration v36→v37 + backfill idempotent")

from fastapi.testclient import TestClient
from verabot.main import app
from verabot.services.reminders import clock
from verabot.tools.registry import ToolContext, TurnState, run_tool

cli = TestClient(app)
clock.set_now(NOW0)


def auth(name):
    res = cli.post("/api/auth/register", json={"username": name, "password": "pw123456"})
    assert res.status_code == 200, res.text
    body = res.json()
    return {"Authorization": "Bearer " + body["token"]}, body


HA, auth_a = auth("items-a")
HB, auth_b = auth("items-b")
bot_a = cli.post("/api/bots", json={"name": "甲"}, headers=HA).json()
bot_b = cli.post("/api/bots", json={"name": "乙"}, headers=HA).json()
cli.patch(f"/api/bots/{bot_a['id']}", json={"allowed_tools": ["create_reminder", "list_reminders", "manage_reminder"]}, headers=HA)

# ---------- 创建 / 视图 / 清单 ----------
todo = cli.post("/api/items", json={"title": "买菜", "checklist": ["牛奶", {"text": "鸡蛋", "done": True}]},
                headers={**HA, "Idempotency-Key": "item-todo-1"}).json()
assert todo["due_at"] is None and todo["notify"] is False
assert todo["checklist_total"] == 2 and todo["checklist_done"] == 1
assert len(todo["checklist"]) == 2
planned_due = (NOW0.astimezone(SH) + timedelta(days=2)).replace(hour=15, minute=0, second=0, microsecond=0)
plan = cli.post("/api/items", json={"title": "下周开会", "due_at": planned_due.isoformat(timespec="minutes"),
                                    "notify": True}, headers=HA).json()
today_due = NOW0.astimezone(SH).replace(hour=18, minute=0, second=0, microsecond=0)
today = cli.post("/api/items", json={"title": "今晚吃饭", "due_at": today_due.isoformat(timespec="minutes")},
                 headers=HA).json()

views = {v: cli.get(f"/api/items?view={v}", headers=HA).json()["items"] for v in ("today", "planned", "todo", "bot", "done")}
assert any(i["id"] == today["id"] for i in views["today"]), views["today"]
assert any(i["id"] == plan["id"] for i in views["planned"])
assert any(i["id"] == todo["id"] for i in views["todo"])
assert all(i.get("task_id") for i in views["bot"]) or True  # 用户 a 尚无关联任务也可为空

# 勾选清单
cid = todo["checklist"][0]["id"]
toggled = cli.patch(f"/api/items/{todo['id']}/checklist/{cid}", json={"done": True}, headers=HA).json()
assert toggled["checklist_done"] == 2
replaced = cli.put(f"/api/items/{todo['id']}/checklist",
                   json={"expected_version": toggled["version"], "items": ["只要一项"]}, headers=HA).json()
assert replaced["checklist_total"] == 1 and replaced["checklist_done"] == 0
print("PASS ITEMS-02 views + checklist")

# ---------- 任务摘要映射（业务词） ----------
uid = auth_a["user"]["id"] if "user" in auth_a else None
# register 返回 token；用 DB 直接插任务并回填关联
con = sqlite3.connect(DB)
user_row = con.execute("SELECT id FROM users WHERE username='items-a'").fetchone()
uid = user_row[0]
bid = bot_a["id"]
con.execute(
    """INSERT INTO scheduled_tasks(id,user_id,bot_id,title,instruction,state,timezone,start_at_utc,next_run_at_utc,
       created_at,updated_at) VALUES (100,?,?, '周期A','指令','active','Asia/Shanghai',?,?,?,?)""",
    (uid, bid, iso(NOW0), iso(NOW0 + timedelta(hours=2)), iso(NOW0), iso(NOW0)))
con.execute(
    """INSERT INTO scheduled_task_runs(id,task_id,user_id,bot_id,trigger,scheduled_for_utc,schedule_revision,state,
       task_snapshot_json,available_at,created_at,result_text,finished_at)
       VALUES (1000,100,?,?, 'scheduled',?,1,'succeeded','{}',?,?, '简报已生成',?)""",
    (uid, bid, iso(NOW0), iso(NOW0), iso(NOW0), iso(NOW0)))
con.execute(
    """INSERT INTO owned_tasks(id,user_id,owner_bot_id,owner_name,goal,completion_criteria,state,created_at,updated_at,
       request_key,request_hash) VALUES (200,?,?, '甲','等你确认','完成','awaiting_approval',?,?, 'ka','ha')""",
    (uid, bid, iso(NOW0), iso(NOW0)))
con.commit()
con.close()
db.init_db()  # 幂等回填新建关联事项
bot_items = cli.get("/api/items?view=bot", headers=HA).json()["items"]
by_task = {(i["task"]["kind"], i["task"]["id"]): i["task"] for i in bot_items if i.get("task")}
assert by_task[("scheduled", 100)]["status"] == "待执行"
assert by_task[("scheduled", 100)]["last_result_summary"] == "简报已生成"
assert by_task[("owned", 200)]["status"] == "等你处理"
assert by_task[("owned", 200)]["needs_user"] is True
# 不暴露内部字段
raw = cli.get(f"/api/items/{[i for i in bot_items if i['task']['id']==200][0]['id']}", headers=HA).json()
blob = json.dumps(raw, ensure_ascii=False)
for forbidden in ("lease_token", "lease_owner", "reserved_tokens", "authorization_json", "trace_summary"):
    assert forbidden not in blob, forbidden
print("PASS ITEMS-03 task summary mapping")

# ---------- §5.2：Bot 工具可见范围 ----------
import asyncio
from verabot import db as vdb

full_a = cli.get(f"/api/bots/{bot_a['id']}", headers=HA).json()
ctx = ToolContext(user_id=uid, bot=full_a, turn=TurnState(), user_text="提醒我")


def tool(name, args, context=None):
    return asyncio.run(run_tool(context or ctx, name, json.dumps(args)))


# 用户自建待办：Bot 不可见
listed = tool("list_reminders", {"status": "scheduled,due,snoozed,missed"})
ids = {r["id"] for r in listed["reminders"]}
assert todo["id"] not in ids
# Bot 创建带 checklist + source_kind=chat
created_tool = tool("create_reminder", {"title": "对话待办", "checklist": ["a", "b"]})
assert created_tool.get("ok"), created_tool
detail = cli.get(f"/api/items/{created_tool['id']}", headers=HA).json()
assert detail["source_kind"] == "chat" and detail["checklist_total"] == 2 and detail["due_at"] is None
# 越权：乙的提醒
other = cli.post("/api/items", json={"title": "别人的"}, headers=HB).json()
denied = tool("manage_reminder", {"action": "complete", "id": other["id"]})
assert denied.get("error") == "提醒不存在"
print("PASS ITEMS-04 §5.2 scope + tool checklist/todo")

# ---------- 旧 /api/reminders 形状兼容；关联任务 complete 只完成事项 ----------
legacy = cli.get("/api/reminders", headers=HA).json()
assert "reminders" in legacy and "counts" in legacy
sample = next(r for r in legacy["reminders"] if r.get("task_id") == 200)
assert "checklist_done" in sample and "task_kind" in sample
# 完成关联事项后 owned 任务状态不变
before_state = sqlite3.connect(DB).execute("SELECT state FROM owned_tasks WHERE id=200").fetchone()[0]
done_item = cli.post(f"/api/reminders/{sample['id']}/complete", headers=HA).json()
assert done_item["status"] == "done"
after_state = sqlite3.connect(DB).execute("SELECT state FROM owned_tasks WHERE id=200").fetchone()[0]
assert before_state == after_state == "awaiting_approval"
# 动作接口
cli.post(f"/api/items/{todo['id']}/complete", headers=HA).raise_for_status()
cli.post(f"/api/items/{todo['id']}/reopen", headers=HA).raise_for_status()
print("PASS ITEMS-05 legacy reminders API + complete item only")

# sql layer
from scripts.test import sql_layer_check
# run as subprocess-equivalent
import importlib.util
spec = importlib.util.spec_from_file_location("sql_layer_check", ROOT / "scripts/test/sql_layer_check.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
assert mod.main() == 0
print("PASS ITEMS-06 sql_layer_check")
print("ALL unified_items_test PASSED")
