#!/usr/bin/env python3
"""删除单条消息 MSG-DEL-01..07：DELETE /api/bots/{bot_id}/messages/{message_id}。
临时 SQLite + FastAPI TestClient，不调用 LLM、不触碰正式数据库。
运行（在 backend/ 下）：uv run python scripts/test/message_delete_test.py
"""
import os, re, sys, tempfile
from pathlib import Path

TMP = tempfile.mkdtemp(prefix="vb_msgdel_")
os.environ["VERABOT_DB"] = str(Path(TMP) / "t.db")
os.environ["VERABOT_DATA_DIR"] = TMP
os.environ.setdefault("DEEPSEEK_API_KEY", "test-not-used")
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "backend"))

from fastapi.testclient import TestClient
from verabot import db
from verabot.main import app

db.init_db()
cli = TestClient(app)


def register(name):
    r = cli.post("/api/auth/register", json={"username": name, "password": "pw123456"}).json()
    return {"Authorization": "Bearer " + r["token"]}, r["user"]["id"]


h, uid = register("deluser")
h2, uid2 = register("delother")
bot = cli.post("/api/bots", json={"name": "A"}, headers=h).json()
bot_b = cli.post("/api/bots", json={"name": "B"}, headers=h).json()
other_bot = cli.post("/api/bots", json={"name": "X"}, headers=h2).json()
m_user = db.add_message(uid, bot["id"], "user", "你好")
m_bot = db.add_message(uid, bot["id"], "assistant", "你好呀", traces=[{"id": "t1", "name": "remember"}])
m_keep = db.add_message(uid, bot["id"], "user", "保留")
m_other = db.add_message(uid2, other_bot["id"], "user", "别人的")

# 引用该消息的行：记忆、通知、提醒（外键 / 触发器置 NULL，行本身保留）
now = db.now_iso()
with db.tx() as c:
    mem = c.execute("INSERT INTO memories(user_id,scope,bot_id,type,content,content_hash,source,source_message_id,status,"
                    "created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                    (uid, "bot", bot["id"], "fact", "不吃香菜", "h1", "explicit_chat", m_bot, "active", now, now)).lastrowid
    ntf = c.execute("INSERT INTO notifications(user_id,category,title,bot_id,message_id,dedupe_key,created_at) "
                    "VALUES (?,?,?,?,?,?,?)", (uid, "bot_message", "t", bot["id"], m_bot, "k1", now)).lastrowid
    rem = c.execute("INSERT INTO reminders(user_id,bot_id,content,created_at,source_message_id) VALUES (?,?,?,?,?)",
                    (uid, bot["id"], "开会", now, m_bot)).lastrowid

RESULTS = []
def check(cid, name, ok):
    RESULTS.append(ok); print(f"[{'PASS' if ok else 'FAIL'}] {cid} {name}", flush=True)

url = lambda b, m: f"/api/bots/{b}/messages/{m}"
ids = lambda: [m["id"] for m in cli.get(f"/api/bots/{bot['id']}/messages", headers=h).json()["messages"]]

r = cli.delete(url(bot["id"], m_bot), headers=h)
check("MSG-DEL-01", "删除自己的 Bot 回复 → 200 {ok:true}", r.status_code == 200 and r.json() == {"ok": True})
check("MSG-DEL-02", "列表不再返回，同一轮的用户消息与其他消息保留", ids() == [m_user, m_keep])

with db.tx() as c:
    mrow = c.execute("SELECT source_message_id, status FROM memories WHERE id=?", (mem,)).fetchone()
    nrow = c.execute("SELECT message_id FROM notifications WHERE id=?", (ntf,)).fetchone()
    rrow = c.execute("SELECT source_message_id FROM reminders WHERE id=?", (rem,)).fetchone()
check("MSG-DEL-03", "已提取的记忆保留（source_message_id 置 NULL），通知 / 提醒引用置 NULL",
      tuple(mrow) == (None, "active") and nrow[0] is None and rrow[0] is None)

r1 = cli.delete(url(bot["id"], 999999), headers=h)                 # 不存在
r2 = cli.delete(url(bot["id"], m_other), headers=h)                # 别人的消息，挂在自己的 Bot 下
r3 = cli.delete(url(other_bot["id"], m_other), headers=h)          # 别人的 Bot + 别人的消息
r4 = cli.delete(url(bot_b["id"], m_user), headers=h)               # 自己的消息，但 Bot 不对
r5 = cli.delete(url(bot["id"], m_bot), headers=h)                  # 已删除，再删一次
same = {(x.status_code, x.text) for x in (r1, r2, r3, r4, r5)}
check("MSG-DEL-04", "不存在 / 他人 / Bot 不匹配 / 重复删除 → 完全相同的 404", same == {(404, r1.text)} and r1.status_code == 404)
with db.tx() as c:
    still = c.execute("SELECT COUNT(*) FROM messages WHERE id IN (?,?)", (m_other, m_user)).fetchone()[0]
check("MSG-DEL-05", "越权请求不删除任何数据", still == 2)

r = cli.delete(url(bot["id"], m_user), headers=h)
check("MSG-DEL-06", "删除用户消息 → 200，只删这一条", r.status_code == 200 and ids() == [m_keep]
      and cli.delete(url(bot["id"], m_keep)).status_code == 401)

# 契约（Contract）：iOS APIClient 的路径 / 方法与后端路由一致
client = (ROOT / "frontend/ios/Packages/VeraBotKit/Sources/VeraBotNetworking/APIClient.swift").read_text()
paths = app.openapi()["paths"]
check("MSG-DEL-07", "iOS 契约：DELETE /api/bots/{bot_id}/messages/{message_id} ↔ deleteMessage(botID:messageID:)",
      "delete" in paths.get("/api/bots/{bot_id}/messages/{message_id}", {})
      and re.search(r'func deleteMessage\(botID: Int, messageID: Int\).*?"/api/bots/\\\(botID\)/messages/\\\(messageID\)", method: "DELETE"',
                    client, re.S) is not None)

print(f"{sum(RESULTS)}/{len(RESULTS)} PASS")
sys.exit(0 if all(RESULTS) else 1)
