"""端到端冒烟测试：uv run python scripts/test/smoke_test.py [base_url]（在 backend/ 下，需要后端运行中）
迭代 2 起新 Bot 默认最小权限（无工具），本脚本创建 Bot 后显式开通工具 / 委派；Bot 上限读取 /api/bots 的 limit（软上限，默认 20）。
未配置 OPENAI_API_KEY 时，语音转写的两项检查记为 SKIP（不算失败）。"""
import json
import sys
import time

import httpx

_args = [a for a in sys.argv[1:] if not a.startswith("--")]
BASE = _args[0] if _args else "http://127.0.0.1:8000"
c = httpx.Client(base_url=BASE, timeout=180)
ok = True


def check(cond, msg):
    global ok
    print(("  ✅ " if cond else "  ❌ ") + msg)
    ok &= bool(cond)


def reg(name):
    r = c.post("/api/auth/register", json={"username": name, "password": "test123456"})
    r.raise_for_status()
    return {"Authorization": "Bearer " + r.json()["token"]}


def chat(h, bot_id, text):
    events, t0, first = [], time.time(), None
    with c.stream("POST", f"/api/bots/{bot_id}/chat", headers=h, json={"message": text}) as r:
        r.raise_for_status()
        ev = None
        for line in r.iter_lines():
            if line.startswith("event:"):
                ev = line[6:].strip()
            elif line.startswith("data:"):
                d = json.loads(line[5:])
                if ev == "delta" and first is None:
                    first = time.time() - t0
                events.append((ev, d))
    text_out = "".join(d["text"] for e, d in events if e == "delta")
    tools = [d for e, d in events if e == "tool_result"]
    errs = [d for e, d in events if e == "error"]
    print(f"  → [{text}] deltas={sum(1 for e, _ in events if e == 'delta')} first_token={first and round(first, 2)}s "
          f"tools={[t['name'] for t in tools]} errors={errs}")
    print("    " + text_out.replace("\n", " ")[:220])
    return text_out, tools, events


sfx = str(int(time.time()))[-6:]
print("1. 注册用户 A")
ha = reg("smoke_a_" + sfx)
print("2. 创建 2 个 Bot")
b1 = c.post("/api/bots", headers=ha, json={"name": "Vera", "avatar": "🦊", "color": "#0f766e",
            "persona": "全能私人助理", "instructions": "简洁回答；专业知识问题请用 ask_bot 咨询 小研"}).json()
b2 = c.post("/api/bots", headers=ha, json={"name": "小研", "avatar": "🔬", "color": "#0369a1",
            "persona": "资深研究员，擅长知识解释", "instructions": "回答不超过 120 字"}).json()
check(b1.get("id") and b2.get("id"), f"bots created: {b1.get('id')}, {b2.get('id')}")
check(b1.get("allowed_tools") == [] and b1.get("accept_delegation") is False, "new bot defaults to least privilege")
r1 = c.patch(f"/api/bots/{b1['id']}", headers=ha, json={"allowed_tools": ["get_weather", "create_reminder", "list_reminders", "ask_bot"],
                                                        "delegate_to": [b2["id"]]})
r2 = c.patch(f"/api/bots/{b2['id']}", headers=ha, json={"accept_delegation": True})
check(r1.status_code == 200 and r2.status_code == 200, "grant tools / delegation via PATCH")
print("3. 流式对话")
t, _, ev = chat(ha, b1["id"], "你好，用一句话介绍你自己")
check(sum(1 for e, _ in ev if e == "delta") > 3 and t, "streaming deltas received")
print("4. 天气工具")
t, tools, _ = chat(ha, b1["id"], "石家庄天气怎么样？")
check(any(x["name"] == "get_weather" and "current" in x["result"] for x in tools), "get_weather called with data")
print("5. 提醒工具")
t, tools, _ = chat(ha, b1["id"], "明天早上9点提醒我给王总回电话")
check(any(x["name"] == "create_reminder" and x["result"].get("ok") for x in tools), "create_reminder ok")
rem = c.get("/api/reminders", headers=ha).json()["reminders"]
check(len(rem) >= 1, f"reminders in DB: {[(r['content'], r['due_at']) for r in rem]}")
print("6. 多 Agent 协作 ask_bot")
t, tools, _ = chat(ha, b1["id"], "请咨询小研：为什么天空是蓝色的？把它的答复总结给我")
ab = [x for x in tools if x["name"] == "ask_bot"]
check(ab and ab[0]["result"].get("answer"), "ask_bot delegated & answered")
if ab:
    print("    trace:", ab[0]["result"]["from_bot"], "→", ab[0]["result"]["to_bot"], "|",
          ab[0]["result"]["answer"][:120].replace("\n", " "))
m2 = c.get(f"/api/bots/{b2['id']}/messages", headers=ha).json()["messages"]
check(len(m2) == 0, "delegation did not pollute 小研's own chat history (context isolation)")
print("7. 记忆：同 Bot 历史")
t, _, _ = chat(ha, b1["id"], "我刚才让你提醒我做什么？")
check("王总" in t or "电话" in t, "per-bot memory recalls earlier turn")
print("8. 隔离：用户 B")
hb = reg("smoke_b_" + sfx)
check(c.get("/api/bots", headers=hb).json()["bots"] == [], "user B sees no bots")
check(c.get(f"/api/bots/{b1['id']}", headers=hb).status_code == 404, "user B GET A's bot → 404")
check(c.get(f"/api/bots/{b1['id']}/messages", headers=hb).status_code == 404, "user B read A's messages → 404")
r = c.post(f"/api/bots/{b1['id']}/chat", headers=hb, json={"message": "hi"})
check(r.status_code == 404, "user B chat with A's bot → 404")
check(c.get("/api/reminders", headers=hb).json()["reminders"] == [], "user B sees no reminders")
bb = c.post("/api/bots", headers=hb, json={"name": "B助手"}).json()
t, tools, _ = chat(hb, bb["id"], "请用 ask_bot 工具咨询 小研：1+1等于几")
ab = [x for x in tools if x["name"] == "ask_bot"]
check(all(x["result"].get("error") for x in ab), f"user B cannot ask_bot A's 小研 ({[x['result'] for x in ab]})")
check(c.get("/api/bots").status_code == 401, "no token → 401")
print("9. Bot 数量上限")
limit = c.get("/api/bots", headers=ha).json()["limit"]
for i in range(limit - 2):
    c.post("/api/bots", headers=ha, json={"name": f"extra{i}"})
r = c.post("/api/bots", headers=ha, json={"name": "extra-over"})
check(r.status_code == 400, f"bot #{limit + 1} rejected (soft limit {limit}): {r.json().get('detail')}")
print("10. 用量看板")
q = c.get("/api/quota", headers=ha).json()
check(q["total"]["total_tokens"] > 0 and q["total"]["requests"] >= 5, f"quota: {q['total']} delegations={q['delegations']}")
print("11. 语音转写 /api/transcribe")
import os
wav = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "zh_sample.webm")
with open(wav, "rb") as f:
    r = c.post("/api/transcribe", headers=ha, files={"file": ("s.webm", f, "audio/webm")}, data={"language": "zh"})
tr = r.json()
print("   ", tr)
no_stt = "OPENAI_API_KEY" in str(tr.get("detail", ""))
if no_stt:
    print("  ⏭️  SKIP transcribe returns Chinese text（未配置 OPENAI_API_KEY）")
else:
    check(r.status_code == 200 and "开会" in tr.get("text", ""), "transcribe returns Chinese text")
check(c.post("/api/transcribe", files={"file": ("s.webm", b"x" * 2000, "audio/webm")}).status_code == 401, "transcribe needs auth")
check(c.post("/api/transcribe", headers=ha, files={"file": ("a.txt", b"x" * 2000, "text/plain")}).status_code == 415, "non-audio → 415")
check(c.post("/api/transcribe", headers=ha, files={"file": ("big.wav", b"\0" * (10 * 1024 * 1024 + 10), "audio/wav")}).status_code == 413, "size limit → 413")
q = c.get("/api/quota", headers=ha).json()
if no_stt:
    print("  ⏭️  SKIP quota transcribe counter（未配置 OPENAI_API_KEY）")
else:
    check(q["transcribe"]["total"]["requests"] == 1, f"quota transcribe counter: {q['transcribe']}")
if "--keep" not in sys.argv:  # 清理本次测试账号（级联删除其 Bot / 消息 / 提醒 / 用量）
    import sqlite3
    db_path = os.getenv("VERABOT_DB", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data", "verabot.db"))
    with sqlite3.connect(db_path) as db:
        db.execute("PRAGMA foreign_keys=ON")
        n = db.execute("DELETE FROM users WHERE username IN (?,?)", ("smoke_a_" + sfx, "smoke_b_" + sfx)).rowcount
    print(f"   cleaned up {n} smoke test accounts")
print("\nRESULT:", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
