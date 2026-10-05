#!/usr/bin/env python3
"""提醒 R1：迁移、状态机、调度补跑、Bot 权限、隔离、契约。不访问外网。"""
import asyncio
import json
import os
import sqlite3
import sys
import tempfile
import threading
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[2]
TMP = tempfile.mkdtemp(prefix="vb_rem_")
DB = str(Path(TMP) / "t.db")
os.environ["VERABOT_DB"] = DB
os.environ["VERABOT_DATA_DIR"] = TMP
os.environ["VERABOT_SCHEDULER"] = "0"
os.environ.setdefault("DEEPSEEK_API_KEY", "test-not-used")
sys.path.insert(0, str(ROOT))

SH = ZoneInfo("Asia/Shanghai")
NOW0 = datetime(2026, 10, 3, 2, 0, tzinfo=timezone.utc)  # 上海 10:00


def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat(timespec="seconds")


# ---------- v10 库，含原文时间 / 已完成 / 过去 / 已删除 Bot ----------
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
  due_at TEXT, done INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL);
CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
INSERT INTO schema_meta VALUES ('version','10');
INSERT INTO users(id, username, password_hash, created_at) VALUES (1,'legacy','x','2026-01-01T00:00:00+00:00');
INSERT INTO bots(id, user_id, name, created_at) VALUES (1,1,'旧助手','2026-01-01T00:00:00+00:00');
""")
recent = (datetime.now(timezone.utc) - timedelta(minutes=30)).isoformat(timespec="seconds")
rows = [
    (1, 1, "A" * 250, "2099-01-01T09:00:00+08:00", 0),
    (2, 1, "原文时间", "明天下午三点", 0),
    (3, 1, "做完了", "2099-06-01T09:00:00+08:00", 1),
    (4, 1, "很久以前", "2020-01-01T09:00:00+08:00", 0),
    (5, 1, "刚刚过期", recent, 0),
    (6, None, "孤儿提醒", "2099-02-01T09:00:00+08:00", 0),
    (7, 1, "没写时间", None, 0),
]
con.executemany("INSERT INTO reminders(id, bot_id, content, due_at, done, user_id, created_at) VALUES (?,?,?,?,?,1,'2026-01-01T00:00:00+00:00')", rows)
con.commit(); con.close()

from verabot import db
db.init_db()
db.init_db()
con = sqlite3.connect(DB)
ver = con.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()[0]
tables = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}
needed = {"reminder_events", "notifications", "notification_deliveries", "notification_prefs", "push_devices", "idempotency_keys"}
cols = {r[1] for r in con.execute("PRAGMA table_info(reminders)")}
backups = list(Path(TMP).glob("*.bak-before-v11-*"))
events = con.execute("SELECT COUNT(*) FROM reminder_events").fetchone()[0]
by_id = {r[0]: r for r in con.execute(
    "SELECT id, title, note, status, due_at, due_utc, created_by, assignee_bot_id, bot_id, completed_at, version FROM reminders ORDER BY id")}
con.close()
assert ver == "14" == str(db.SCHEMA_VERSION), ver  # v13 = MCP 连接器凭据，v14 = 记忆 M2
assert needed <= tables, needed - tables
assert {"title", "status", "due_utc", "rrule", "version", "assignee_bot_id"} <= cols
assert len(backups) == 1, backups
assert events == 7, events
assert by_id[1][1] == "A" * 200 and by_id[1][2].startswith("A" * 50) and by_id[1][3] == "scheduled" and by_id[1][5]
assert by_id[2][4] is None and "原时间：明天下午三点" in (by_id[2][2] or "") and by_id[2][3] == "scheduled"
assert by_id[3][3] == "done" and by_id[3][9] is None
assert by_id[4][3] == "missed"
assert by_id[5][3] == "due"
assert by_id[6][3] == "scheduled" and by_id[6][7] is None and by_id[6][8] is None and by_id[6][6] == "bot"
assert by_id[7][3] == "scheduled" and by_id[7][4] is None
assert all(r[10] == 1 and r[6] == "bot" for r in by_id.values())
db.init_db()
con = sqlite3.connect(DB)
assert con.execute("SELECT COUNT(*) FROM reminder_events").fetchone()[0] == 7
assert len(list(Path(TMP).glob("*.bak-before-v11-*"))) == 1
con.close()
print("PASS REM-01 migration v10→v11")

from fastapi.testclient import TestClient
from verabot.main import app
from verabot.services.reminders import clock, scheduler, service
from verabot.tools.registry import ToolContext, TurnState, run_tool

cli = TestClient(app)
clock.set_now(NOW0)


def auth(name):
    res = cli.post("/api/auth/register", json={"username": name, "password": "pw123456"})
    assert res.status_code == 200, res.text
    body = res.json()
    return {"Authorization": "Bearer " + body["token"]}, body


HA, auth_a = auth("rem-a")
HB, auth_b = auth("rem-b")
bot_a = cli.post("/api/bots", json={"name": "甲"}, headers=HA).json()
bot_b = cli.post("/api/bots", json={"name": "乙"}, headers=HA).json()
bot_other = cli.post("/api/bots", json={"name": "别人的"}, headers=HB).json()
cli.patch(f"/api/bots/{bot_a['id']}", json={"allowed_tools": ["create_reminder", "list_reminders", "manage_reminder"]}, headers=HA)
cli.patch(f"/api/bots/{bot_b['id']}", json={"allowed_tools": ["create_reminder", "list_reminders"]}, headers=HA)


def create(**kw):
    res = cli.post("/api/reminders", json=kw, headers=HA)
    return res


due_today = "2026-10-03T15:00:00+08:00"
made = create(title="交周报", due_at=due_today, timezone="Asia/Shanghai", priority=2)
assert made.status_code == 201, made.text
body = made.json()
assert body["version"] == 1 and body["content"] == "交周报" and body["done"] == 0 and body["status"] == "scheduled"
assert body["due_utc"].startswith("2026-10-03T07:00")
rid = body["id"]
got = cli.get(f"/api/reminders/{rid}", headers=HA)
assert got.status_code == 200 and got.json()["title"] == "交周报"
patched = cli.patch(f"/api/reminders/{rid}", json={"expected_version": 1, "note": "附注", "priority": 3}, headers=HA)
assert patched.status_code == 200 and patched.json()["version"] == 2 and patched.json()["note"] == "附注"
deleted = cli.delete(f"/api/reminders/{rid}", headers=HA)
assert deleted.status_code == 200 and deleted.json()["status"] == "cancelled" and deleted.json()["done"] == 0
print("PASS REM-02 crud")

assert "不能把提醒设在过去" in create(title="过去", due_at="2020-01-01T09:00:00+08:00").text
assert "时区无效" in create(title="时区", due_at="2026-10-04T09:00:00+08:00", timezone="Not/AZone").text
assert "不支持的重复规则" in create(title="规则", due_at="2026-10-04T09:00:00+08:00", rrule="FREQ=HOURLY").text
assert "标题最多 200 个字" in create(title="字" * 201, due_at="2026-10-04T09:00:00+08:00").text
print("PASS REM-03 validation")

clock.set_now(NOW0)
one = create(title="到时", due_at="2026-10-03T10:05:00+08:00").json()
clock.set_now(datetime(2026, 10, 3, 2, 6, tzinfo=timezone.utc))
stats = scheduler.tick()
assert stats["fired"] >= 1
again = service.get_reminder(auth_a["user"]["id"], one["id"])
assert again["status"] == "due"
with db.tx() as c:
    fired = c.execute("SELECT COUNT(*) FROM reminder_events WHERE reminder_id=? AND kind='fired'", (one["id"],)).fetchone()[0]
    notes = c.execute("SELECT COUNT(*) FROM notifications WHERE reminder_id=?", (one["id"],)).fetchone()[0]
assert fired == 1 and notes == 1, (fired, notes)
scheduler.tick()
with db.tx() as c:
    fired2 = c.execute("SELECT COUNT(*) FROM reminder_events WHERE reminder_id=? AND kind='fired'", (one["id"],)).fetchone()[0]
    notes2 = c.execute("SELECT COUNT(*) FROM notifications WHERE reminder_id=?", (one["id"],)).fetchone()[0]
assert fired2 == 1 and notes2 == 1
print("PASS REM-04 fire once")

clock.set_now(datetime(2026, 10, 4, 3, 0, tzinfo=timezone.utc))
scheduler.tick()
missed = service.get_reminder(auth_a["user"]["id"], one["id"])
assert missed["status"] == "missed", missed["status"]
done = cli.post(f"/api/reminders/{one['id']}/complete", json={}, headers=HA)
assert done.status_code == 200 and done.json()["status"] == "done" and done.json()["done"] == 1
print("PASS REM-05 missed then complete")

clock.set_now(NOW0)
snooze_item = create(title="稍后", due_at="2026-10-03T18:00:00+08:00").json()
original_due = snooze_item["due_at"]
sn = cli.post(f"/api/reminders/{snooze_item['id']}/snooze", json={"minutes": 10}, headers=HA)
assert sn.status_code == 200 and sn.json()["status"] == "snoozed" and sn.json()["due_at"] == original_due
clock.set_now(NOW0 + timedelta(minutes=11))
scheduler.tick()
woke = service.get_reminder(auth_a["user"]["id"], snooze_item["id"])
assert woke["status"] == "due", woke["status"]
print("PASS REM-06 snooze")

clock.set_now(NOW0)
series = create(title="每天", due_at="2026-10-04T09:00:00+08:00", rrule="FREQ=DAILY;COUNT=3").json()
first = cli.post(f"/api/reminders/{series['id']}/complete", json={}, headers=HA).json()
assert first["status"] == "scheduled" and first["due_at"].startswith("2026-10-05")
second = cli.post(f"/api/reminders/{series['id']}/skip", json={}, headers=HA).json()
assert second["status"] == "scheduled" and second["due_at"].startswith("2026-10-06")
third = cli.post(f"/api/reminders/{series['id']}/complete", json={}, headers=HA).json()
assert third["status"] == "done", third
# 错过：先到时，再跨过下一次
clock.set_now(NOW0)
daily = create(title="会错过", due_at="2026-10-03T11:00:00+08:00", rrule="FREQ=DAILY").json()
clock.set_now(datetime(2026, 10, 3, 3, 1, tzinfo=timezone.utc))
scheduler.tick()
assert service.get_reminder(auth_a["user"]["id"], daily["id"])["status"] == "due"
old_due = service.get_reminder(auth_a["user"]["id"], daily["id"])["due_utc"]
clock.set_now(datetime(2026, 10, 4, 3, 2, tzinfo=timezone.utc))
scheduler.tick()
after = service.get_reminder(auth_a["user"]["id"], daily["id"])
assert after["due_utc"] > old_due and after["status"] == "scheduled", after
with db.tx() as c:
    missed_n = c.execute("SELECT COUNT(*) FROM reminder_events WHERE reminder_id=? AND kind='missed'", (daily["id"],)).fetchone()[0]
assert missed_n == 1
print("PASS REM-07 recurrence")

clock.set_now(datetime(2026, 1, 1, tzinfo=timezone.utc))
month = create(title="月底", due_at="2026-01-31T09:00:00+08:00", rrule="FREQ=MONTHLY;BYMONTHDAY=31", timezone="Asia/Shanghai").json()
fires = month["next_fires"]
local_days = [datetime.fromisoformat(x).astimezone(SH).day for x in fires[:4]]
assert local_days[0] == 31 and 2 not in [datetime.fromisoformat(x).astimezone(SH).month for x in fires[:3] if datetime.fromisoformat(x).astimezone(SH).day != 31]
assert all(datetime.fromisoformat(x).astimezone(SH).day == 31 for x in fires[:4]), fires
work = create(title="上班", due_at="2026-10-05T09:00:00+08:00", rrule="FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR").json()
weekdays = [datetime.fromisoformat(x).astimezone(SH).weekday() for x in work["next_fires"][:10]]
assert weekdays and all(d < 5 for d in weekdays), weekdays
clock.set_now(datetime(2026, 3, 6, 12, tzinfo=timezone.utc))
ny = create(title="纽约", due_at="2026-03-07T09:00:00", timezone="America/New_York", rrule="FREQ=DAILY").json()
hours = []
for raw in ny["next_fires"][:5]:
    local = datetime.fromisoformat(raw).astimezone(ZoneInfo("America/New_York"))
    hours.append(local.hour)
assert hours == [9, 9, 9, 9, 9], (hours, ny["next_fires"][:5])
print("PASS REM-08 next fires")

clock.set_now(datetime(2026, 10, 1, 0, 0, tzinfo=timezone.utc))
catch = create(title="补跑", due_at="2026-10-01T09:00:00+08:00", rrule="FREQ=DAILY").json()
clock.set_now(datetime(2026, 10, 4, 0, 0, tzinfo=timezone.utc))  # 上海 10月4日 08:00，10月4日 09:00 还没到
with db.tx() as c:
    before_notes = c.execute("SELECT COUNT(*) FROM notifications WHERE reminder_id=?", (catch["id"],)).fetchone()[0]
scheduler.tick()
caught = service.get_reminder(auth_a["user"]["id"], catch["id"])
with db.tx() as c:
    ev = db.rows(c.execute("SELECT kind, detail FROM reminder_events WHERE reminder_id=? AND kind='missed'", (catch["id"],)).fetchall())
    after_notes = c.execute("SELECT COUNT(*) FROM notifications WHERE reminder_id=?", (catch["id"],)).fetchone()[0]
assert len(ev) == 1, ev
detail = json.loads(ev[0]["detail"])
assert detail["missed_count"] == 3, detail
assert caught["status"] == "scheduled" and caught["due_utc"] > iso(clock.now())
assert after_notes == before_notes == 0
print("PASS REM-09 catch-up")

cancelled = create(title="取消后完成", due_at="2026-10-10T09:00:00+08:00").json()
assert cli.delete(f"/api/reminders/{cancelled['id']}", headers=HA).status_code == 200
bad = cli.post(f"/api/reminders/{cancelled['id']}/complete", json={}, headers=HA)
assert bad.status_code == 409 and bad.json()["detail"]["code"] == "invalid_transition"
print("PASS REM-10 invalid transition")

clock.set_now(NOW0)
race = create(title="并发", due_at="2026-10-03T10:01:00+08:00").json()
clock.set_now(datetime(2026, 10, 3, 2, 2, tzinfo=timezone.utc))
barrier = threading.Barrier(2)
outs = {}

def do_tick():
    barrier.wait()
    outs["tick"] = scheduler.tick()

def do_complete():
    barrier.wait()
    try:
        outs["user"] = service.complete_reminder(auth_a["user"]["id"], race["id"], actor="user", client="ios")
    except service.ReminderError as exc:
        outs["err"] = exc.code

threads = [threading.Thread(target=do_tick), threading.Thread(target=do_complete)]
for t in threads:
    t.start()
for t in threads:
    t.join()
final = service.get_reminder(auth_a["user"]["id"], race["id"])
with db.tx() as c:
    kinds = [r[0] for r in c.execute(
        "SELECT kind FROM reminder_events WHERE reminder_id=? AND kind IN ('fired','completed')", (race["id"],))]
assert final["status"] in {"due", "done"}, (final["status"], outs)
assert len(kinds) == 1, (kinds, outs, final["status"])
assert final["version"] >= 2
print("PASS REM-11 concurrency")

clock.set_now(NOW0)
lock = create(title="锁", due_at="2026-10-08T09:00:00+08:00").json()
stale = cli.patch(f"/api/reminders/{lock['id']}", json={"expected_version": 0, "title": "旧"}, headers=HA)
assert stale.status_code == 409 and stale.json()["detail"]["code"] == "version_conflict"
assert stale.json()["detail"]["reminder"]["title"] == "锁"
print("PASS REM-12 version")

idem = create(title="幂等", due_at="2026-10-09T09:00:00+08:00").json()
headers = {**HA, "Idempotency-Key": "done-once"}
a = cli.post(f"/api/reminders/{idem['id']}/complete", json={}, headers=headers)
b = cli.post(f"/api/reminders/{idem['id']}/complete", json={}, headers=headers)
assert a.status_code == 200 and b.status_code == 200 and a.json() == b.json()
with db.tx() as c:
    n_completed = c.execute("SELECT COUNT(*) FROM reminder_events WHERE reminder_id=? AND kind='completed'", (idem["id"],)).fetchone()[0]
assert n_completed == 1
print("PASS REM-13 idempotency")

clock.set_now(NOW0)
soft = create(title="软删除", due_at="2026-10-11T09:00:00+08:00").json()
cli.delete(f"/api/reminders/{soft['id']}", headers=HA)
restored = cli.post(f"/api/reminders/{soft['id']}/restore", headers=HA)
assert restored.status_code == 200 and restored.json()["status"] == "scheduled"
cli.delete(f"/api/reminders/{soft['id']}", headers=HA)
with db.tx() as c:
    c.execute("UPDATE reminders SET cancelled_at=? WHERE id=?", (iso(NOW0 - timedelta(days=31)), soft["id"]))
too_old = cli.post(f"/api/reminders/{soft['id']}/restore", headers=HA)
assert too_old.status_code == 409
clock.set_now(NOW0)
scheduler.tick()
assert cli.get(f"/api/reminders/{soft['id']}", headers=HA).status_code == 404
print("PASS REM-14 restore and purge")

clock.set_now(NOW0)
legacy = create(title="浇水", due_at="2026-10-12T20:00:00+08:00", assignee_bot_id=bot_a["id"]).json()
listed = cli.get("/api/reminders", headers=HA).json()["reminders"]
row = next(x for x in listed if x["id"] == legacy["id"])
assert row["content"] == "浇水" and "due_at" in row and "done" in row and "bot_name" in row
old = cli.post(f"/api/reminders/{legacy['id']}/done", headers=HA)
assert old.status_code == 200 and old.json() == {"ok": True}
assert service.get_reminder(auth_a["user"]["id"], legacy["id"])["done"] == 1
assert cli.post(f"/api/reminders/{legacy['id']}/done", headers=HA).status_code == 200
print("PASS REM-15 legacy done")


def tool(bot, name, args, depth=0, turn=None):
    ctx = ToolContext(auth_a["user"]["id"], bot, depth=depth, turn=turn or TurnState())
    return asyncio.run(run_tool(ctx, name, json.dumps(args)))


full_a = cli.get(f"/api/bots/{bot_a['id']}", headers=HA).json()
full_b = cli.get(f"/api/bots/{bot_b['id']}", headers=HA).json()
clock.set_now(NOW0)
mine = tool(full_a, "create_reminder", {"title": "甲的提醒", "due_at": "2026-10-06T09:00:00+08:00"})
assert mine.get("ok") and mine["id"]
user_only = create(title="用户自己的", due_at="2026-10-06T11:00:00+08:00").json()
assigned = create(title="派给甲", due_at="2026-10-06T12:00:00+08:00", assignee_bot_id=bot_a["id"]).json()
other = tool(full_b, "create_reminder", {"content": "乙的提醒", "due_at": "2026-10-06T13:00:00+08:00"})
listed_bot = tool(full_a, "list_reminders", {})
ids = {item["id"] for item in listed_bot["reminders"]}
assert mine["id"] in ids and assigned["id"] in ids
assert user_only["id"] not in ids and other["id"] not in ids
print("PASS REM-BOT-01 list scope")

denied = tool(full_a, "manage_reminder", {"action": "complete", "id": other["id"]})
assert denied.get("error") == "提醒不存在"
with db.tx() as c:
    audits = c.execute("SELECT detail FROM audit_log WHERE user_id=? AND kind='tool_denied' ORDER BY id DESC LIMIT 5",
                       (auth_a["user"]["id"],)).fetchall()
assert any("reminder_scope" in (row[0] or "") for row in audits), audits
print("PASS REM-BOT-02 scope audit")

no_manage = tool(full_b, "manage_reminder", {"action": "complete", "id": other["id"]})
assert no_manage.get("code") == "tool_not_allowed"
print("PASS REM-BOT-03 tool not allowed")

delegated = tool(full_a, "list_reminders", {}, depth=1)
assert delegated.get("code") == "reminder_not_delegable"
assert tool(full_a, "create_reminder", {"title": "不行"}, depth=1).get("code") == "reminder_not_delegable"
print("PASS REM-BOT-04 delegation blocked")

bad_time = tool(full_a, "create_reminder", {"title": "听不懂", "due_at": "明天下午三点"})
past = tool(full_a, "create_reminder", {"title": "昨天", "due_at": "2020-01-02T09:00:00+08:00"})
assert bad_time.get("error") and not bad_time.get("ok")
assert past.get("error") and "过去" in past["error"]
with db.tx() as c:
    leaked = c.execute("SELECT COUNT(*) FROM reminders WHERE title IN ('听不懂','昨天')").fetchone()[0]
assert leaked == 0
print("PASS REM-BOT-05 no raw time")

turn = TurnState()
dup1 = tool(full_a, "create_reminder", {"title": "同一件", "due_at": "2026-10-07T09:00:00+08:00"}, turn=turn)
dup2 = tool(full_a, "create_reminder", {"title": "同一件", "due_at": "2026-10-07T09:00:00+08:00"}, turn=turn)
assert dup1["id"] == dup2["id"]
with db.tx() as c:
    assert c.execute("SELECT COUNT(*) FROM reminders WHERE title='同一件'").fetchone()[0] == 1
print("PASS REM-BOT-06 dedupe")

turn = TurnState()
for i in range(5):
    res = tool(full_a, "create_reminder", {"title": f"写{i}", "due_at": f"2026-10-2{i}T09:00:00+08:00"}, turn=turn)
    assert res.get("ok"), res
sixth = tool(full_a, "create_reminder", {"title": "第六", "due_at": "2026-11-01T09:00:00+08:00"}, turn=turn)
assert "上限" in sixth.get("error", "")
print("PASS REM-BOT-07 write limit")

kept = tool(full_a, "create_reminder", {"title": "删掉 Bot 还在", "due_at": "2026-12-01T09:00:00+08:00"})
assert cli.delete(f"/api/bots/{bot_a['id']}", headers=HA).status_code == 200
left = cli.get(f"/api/reminders/{kept['id']}", headers=HA).json()
assert left["title"] == "删掉 Bot 还在" and left["bot_id"] is None and left["source_bot_id"] is None
assert left["assignee_bot_id"] is None and left["bot_name"] is None
print("PASS REM-BOT-09 bot deleted keeps reminder")

tools = cli.get("/api/tools", headers=HA).json()["tools"]
managed = next(t for t in tools if t["name"] == "manage_reminder")
assert managed["plugin_id"] == "builtin_reminder" and managed["label"] == "管理提醒"
print("PASS REM-BOT-10 tools plugin id")

# 隔离
for path, method in [
    (f"/api/reminders/{kept['id']}", "get"),
    (f"/api/reminders/{kept['id']}/events", "get"),
    (f"/api/reminders/{kept['id']}/complete", "post"),
    (f"/api/reminders/{kept['id']}/snooze", "post"),
    (f"/api/reminders/{kept['id']}", "delete"),
]:
    if method == "get":
        res = cli.get(path, headers=HB)
    elif method == "delete":
        res = cli.delete(path, headers=HB)
    else:
        res = cli.post(path, headers=HB, json={"minutes": 10} if "snooze" in path else {})
    assert res.status_code == 404, (path, res.status_code, res.text)
assert "Cache-Control" in cli.get("/api/reminders", headers=HA).headers
assert "no-store" in cli.get("/api/reminders", headers=HA).headers["cache-control"]
assert "no-store" in cli.get(f"/api/reminders/{kept['id']}", headers=HA).headers["cache-control"]
foreign_bot = cli.post("/api/reminders", json={"title": "越权", "assignee_bot_id": bot_other["id"]}, headers=HA)
assert foreign_bot.status_code == 404
with db.tx() as c:
    mid = c.execute(
        "INSERT INTO messages(user_id, bot_id, role, content, created_at) VALUES (?,?,?,?,?)",
        (auth_b["user"]["id"], bot_other["id"], "user", "别人的消息", iso(NOW0))).lastrowid
foreign_msg = cli.post("/api/reminders", json={"title": "越权消息", "source_message_id": mid}, headers=HA)
assert foreign_msg.status_code == 404, foreign_msg.text
print("PASS ISO-REM-01/02/03")

core = (ROOT.parent / "frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore")
reminder_swift = (core / "Reminders.swift").read_text()
sample = cli.get(f"/api/reminders/{kept['id']}", headers=HA).json()
expected = {
    "id", "title", "content", "note", "due_at", "due_utc", "timezone", "all_day", "rrule", "repeat_label",
    "next_fires", "status", "snoozed_until", "priority", "created_by", "bot_id", "source_bot_id", "bot_name",
    "assignee_bot_id", "assignee_bot_name", "source_message_id", "notify", "alert_offsets", "version", "done",
    "completed_at", "cancelled_at", "created_at", "updated_at",
}
assert expected <= set(sample), expected - set(sample)
for key in ["due_at", "due_utc", "timezone", "all_day", "rrule", "repeat_label", "next_fires", "snoozed_until",
            "created_by", "source_bot_id", "assignee_bot_id", "assignee_bot_name", "source_message_id",
            "notify", "alert_offsets", "version", "completed_at", "cancelled_at", "updated_at", "bot_name"]:
    assert f'"{key}"' in reminder_swift, key
print("PASS REM-CONTRACT")
print("REMINDER TESTS PASS")
