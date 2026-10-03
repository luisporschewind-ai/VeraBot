#!/usr/bin/env python3
"""通知 R1：偏好、免打扰、限流、设备、退出禁用、无 APNs、契约。不访问外网。"""
import json
import os
import sqlite3
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TMP = tempfile.mkdtemp(prefix="vb_ntf_")
os.environ["VERABOT_DB"] = str(Path(TMP) / "t.db")
os.environ["VERABOT_DATA_DIR"] = TMP
os.environ["VERABOT_SCHEDULER"] = "0"
os.environ.setdefault("DEEPSEEK_API_KEY", "test-not-used")
sys.path.insert(0, str(ROOT))

from fastapi.testclient import TestClient

from verabot import db
from verabot.main import app
from verabot.services.auth import revoke_for_email_claim
from verabot.services.notify.devices import token_log_ref
from verabot.services.notify.dispatcher import delivery_rows, notify, push_payload, uid_hash
from verabot.services.reminders import clock, scheduler

db.init_db()
cli = TestClient(app)
NOW = datetime(2026, 10, 3, 2, 0, tzinfo=timezone.utc)  # 上海 10:00
clock.set_now(NOW)


def auth(name):
    res = cli.post("/api/auth/register", json={"username": name, "password": "pw123456"})
    assert res.status_code == 200, res.text
    body = res.json()
    return {"Authorization": "Bearer " + body["token"]}, body


HA, auth_a = auth("ntf-a")
HB, auth_b = auth("ntf-b")
uid = auth_a["user"]["id"]
bot = cli.post("/api/bots", json={"name": "甲"}, headers=HA).json()
reg = cli.post("/api/devices", json={
    "device_id": "dev-a", "platform": "ios", "local_reminders": True,
    "apns_token": "token-secret-ABCDEF", "timezone": "Asia/Shanghai",
}, headers=HA)
assert reg.status_code == 200, reg.text
assert reg.json()["local_reminders"] is True
assert "no-store" in reg.headers["cache-control"]
print("PASS NTF-01 device register")


def channels(nid):
    return delivery_rows(uid, nid)


note = notify(uid, category="reminder", title="开会", body="备注不该出现", bot_id=bot["id"],
              link="reminder/1", thread_id="reminders", dedupe_key="reminder:1:once",
              created_by="user")
rows = channels(note["id"])
assert {r["channel"] for r in rows} == {"inbox", "local"}
assert all(r["channel"] != "apns" for r in rows)
assert next(r for r in rows if r["channel"] == "local")["state"] == "scheduled_local"
again = notify(uid, category="reminder", title="开会", body=None, dedupe_key="reminder:1:once", created_by="user")
assert again["id"] == note["id"]
print("PASS NTF-11 no apns rows and dedupe")

listed = cli.get("/api/notifications", headers=HA)
assert listed.status_code == 200 and "no-store" in listed.headers["cache-control"]
assert listed.json()["unread_count"] == 1
assert "备注" not in json.dumps(listed.json())
summary = cli.get("/api/notifications/summary", headers=HA)
assert summary.json()["unread_count"] == 1 and "no-store" in summary.headers["cache-control"]
marked = cli.post(f"/api/notifications/{note['id']}/read", headers=HA)
assert marked.json()["read_at"]
unread = cli.post(f"/api/notifications/{note['id']}/unread", headers=HA)
assert unread.json()["read_at"] is None
assert cli.post("/api/notifications/read-all", json={}, headers=HA).json()["updated"] == 1
assert cli.get("/api/notifications/summary", headers=HA).json()["unread_count"] == 0
print("PASS NTF-02 inbox read")

prefs = cli.get("/api/notification-settings", headers=HA)
assert prefs.json()["preview"] == "title" and prefs.json()["quiet_enabled"] is False
assert "no-store" in prefs.headers["cache-control"]
patched = cli.patch("/api/notification-settings", json={
    "quiet_enabled": True, "quiet_start": "23:00", "quiet_end": "08:00", "quiet_timezone": "Asia/Shanghai",
    "preview": "title", "muted_bots": [bot["id"]],
}, headers=HA)
assert patched.status_code == 200, patched.text
assert patched.json()["quiet_enabled"] is True
bad_tz = cli.patch("/api/notification-settings", json={"quiet_timezone": "Not/AZone"}, headers=HA)
assert bad_tz.status_code == 422
missing_bot = cli.patch("/api/notification-settings", json={"muted_bots": [99999]}, headers=HA)
assert missing_bot.status_code == 404
print("PASS NTF-03 prefs")

cli.patch("/api/notification-settings", json={"muted_bots": []}, headers=HA)
clock.set_now(datetime(2026, 10, 3, 15, 30, tzinfo=timezone.utc))  # 上海 23:30
quiet_msg = notify(uid, category="bot_message", title="夜间正文", body="不该上锁", bot_id=bot["id"],
                   dedupe_key="bm:quiet", created_by="bot")
quiet_rows = channels(quiet_msg["id"])
local = next(r for r in quiet_rows if r["channel"] == "local")
assert local["state"] == "suppressed" and local["last_error"] == "quiet_hours", quiet_rows
quiet_rem = notify(uid, category="reminder", title="夜间提醒", body=None, dedupe_key="reminder:quiet",
                   created_by="user", link="reminder/2", thread_id="reminders")
rem_local = next(r for r in channels(quiet_rem["id"]) if r["channel"] == "local")
assert rem_local["state"] == "scheduled_local", rem_local
print("PASS NTF-04 quiet hours spare reminders")

cli.patch("/api/notification-settings", json={"quiet_enabled": False, "muted_bots": []}, headers=HA)
clock.set_now(datetime(2026, 10, 4, 2, 0, tzinfo=timezone.utc))
for i in range(3):
    item = notify(uid, category="bot_message", title=f"第{i}", body="正文", bot_id=bot["id"],
                  dedupe_key=f"bm:rate:{i}", created_by="bot")
    local_row = next(r for r in channels(item["id"]) if r["channel"] == "local")
    assert local_row["last_error"] == "no_apns", local_row
fourth = notify(uid, category="bot_message", title="第四条", body="正文", bot_id=bot["id"],
                dedupe_key="bm:rate:3", created_by="bot")
fourth_local = next(r for r in channels(fourth["id"]) if r["channel"] == "local")
assert fourth_local["state"] == "suppressed" and fourth_local["last_error"] == "rate_bot", fourth_local
con = sqlite3.connect(os.environ["VERABOT_DB"])
counted = con.execute(
    "SELECT COUNT(*) FROM notifications WHERE user_id=? AND category='bot_message'", (uid,)
).fetchone()[0]
con.close()
assert counted >= 4
print("PASS NTF-05 sqlite rate limit")

sensitive = notify(uid, category="system", title="密码是 123456", body="卡号 999", sensitive=True,
                   dedupe_key="sys:secret", created_by="system")
assert sensitive["title"] == "你有一条新通知" and sensitive["body"] is None and sensitive["sensitive"] is True
payload = push_payload(sensitive, uid_hash=uid_hash(uid))
blob = json.dumps(payload, ensure_ascii=False)
assert "123456" not in blob and "999" not in blob
assert payload["aps"]["alert"]["title"] == "你有一条新通知"
assert token_log_ref("token-secret-ABCDEF") == "ABCDEF"
print("PASS NTF-06 preview and token log")

opened = cli.post(f"/api/notifications/{note['id']}/events", json={
    "event": "opened", "channel": "local", "device_id": "dev-a",
}, headers=HA)
assert opened.status_code == 200 and opened.json()["state"] == "opened", opened.text
later = cli.post(f"/api/notifications/{note['id']}/events", json={
    "event": "delivered", "channel": "local", "device_id": "dev-a",
}, headers=HA)
assert later.json()["state"] == "opened", later.text
print("PASS NTF-07 delivery rank")

moved = cli.post("/api/devices", json={
    "device_id": "dev-b", "platform": "ios", "local_reminders": True, "apns_token": "token-secret-ABCDEF",
}, headers=HB)
assert moved.status_code == 200, moved.text
con = sqlite3.connect(os.environ["VERABOT_DB"])
tokens = con.execute(
    "SELECT user_id, device_id, apns_token FROM push_devices WHERE apns_token IS NOT NULL"
).fetchall()
con.close()
assert tokens == [(auth_b["user"]["id"], "dev-b", "token-secret-ABCDEF")], tokens
print("PASS NTF-10 token moves to the new account")

HC, auth_c = auth("ntf-c")
cli.post("/api/devices", json={"device_id": "dev-c", "platform": "ios", "local_reminders": True}, headers=HC)
out = cli.post("/api/auth/logout", json={"refresh_token": auth_c["refresh_token"]})
assert out.status_code == 200
con = sqlite3.connect(os.environ["VERABOT_DB"])
disabled = con.execute(
    "SELECT disabled_at FROM push_devices WHERE user_id=? AND device_id='dev-c'", (auth_c["user"]["id"],)
).fetchone()[0]
assert disabled
HD, auth_d = auth("ntf-d")
cli.post("/api/devices", json={"device_id": "dev-d", "platform": "ios"}, headers=HD)
assert cli.post("/api/auth/logout-all", headers=HD).status_code == 200
disabled_d = con.execute(
    "SELECT disabled_at FROM push_devices WHERE user_id=?", (auth_d["user"]["id"],)
).fetchone()[0]
assert disabled_d
HE, auth_e = auth("ntf-e")
cli.post("/api/devices", json={"device_id": "dev-e", "platform": "ios"}, headers=HE)
revoke_for_email_claim(auth_e["user"]["id"])
disabled_e = con.execute(
    "SELECT disabled_at FROM push_devices WHERE user_id=?", (auth_e["user"]["id"],)
).fetchone()[0]
con.close()
assert disabled_e
print("PASS NTF-08 logout disables devices")

# 提醒到时：有设备、无 apns 行
clock.set_now(NOW)
created = cli.post("/api/reminders", json={
    "title": "一分钟后", "due_at": "2026-10-03T10:05:00+08:00", "timezone": "Asia/Shanghai", "notify": True,
}, headers=HA)
assert created.status_code == 201, created.text
clock.set_now(NOW + timedelta(minutes=6))
stats = scheduler.tick()
assert stats["fired"] >= 1, stats
con = sqlite3.connect(os.environ["VERABOT_DB"])
apns = con.execute("SELECT COUNT(*) FROM notification_deliveries WHERE channel='apns'").fetchone()[0]
con.close()
assert apns == 0
print("PASS NTF-11 scheduler creates no apns")

foreign = cli.get("/api/notifications", headers=HB)
assert all(item["id"] != note["id"] for item in foreign.json()["notifications"])
assert cli.post(f"/api/notifications/{note['id']}/read", headers=HB).status_code == 404
assert cli.delete(f"/api/notifications/{note['id']}", headers=HB).status_code == 404
assert "no-store" in cli.get("/api/notifications", headers=HA).headers["cache-control"]
assert "no-store" in cli.get("/api/notification-settings", headers=HA).headers["cache-control"]
print("PASS NTF isolation and no-store")

swift = (ROOT.parent / "frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore/Notifications.swift").read_text()
sample = cli.get("/api/notifications", headers=HA).json()["notifications"][0]
for key in ("id", "category", "title", "thread_id", "bot_id", "reminder_id", "message_id", "plugin_id",
            "created_at", "read_at", "opened_at"):
    assert key in sample
    assert f'"{key}"' in swift, key
settings = cli.get("/api/notification-settings", headers=HA).json()
for key in ("enabled", "categories", "muted_bots", "quiet_enabled", "quiet_start", "quiet_end",
            "quiet_timezone", "preview"):
    assert key in settings and f'"{key}"' in swift, key
device = cli.post("/api/devices", json={"device_id": "dev-a2", "platform": "ios"}, headers=HA).json()
for key in ("device_id", "platform", "apns_token", "apns_env", "app_version", "os_version", "timezone",
            "local_reminders"):
    assert key in device and f'"{key}"' in swift, key
print("PASS NTF-CONTRACT")
print("NOTIFY TESTS PASS")
