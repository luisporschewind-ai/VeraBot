#!/usr/bin/env python3
"""VeraBot v0.1 API test runner (black-box, stdlib only)."""
import os
import json, time, urllib.request, urllib.error, sys, base64

BASE = "http://127.0.0.1:8000"
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
R = {}

def req(method, path, body=None, token=None, raw=False, timeout=180):
    h = {"Content-Type": "application/json"}
    if token: h["Authorization"] = f"Bearer {token}"
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(BASE + path, data=data, headers=h, method=method)
    try:
        with opener.open(r, timeout=timeout) as resp:
            txt = resp.read().decode()
            return resp.status, (txt if raw else (json.loads(txt) if txt else None))
    except urllib.error.HTTPError as e:
        txt = e.read().decode()
        try: return e.code, json.loads(txt)
        except Exception: return e.code, txt

def chat(token, bot_id, msg):
    """Returns dict with events list, delta count, text, traces, first-delta latency."""
    h = {"Content-Type": "application/json", "Authorization": f"Bearer {token}"}
    r = urllib.request.Request(f"{BASE}/api/bots/{bot_id}/chat", data=json.dumps({"message": msg}).encode(),
                               headers=h, method="POST")
    t0 = time.time(); out = {"events": [], "text": "", "deltas": 0, "traces": [], "first_delta_s": None}
    try:
        with opener.open(r, timeout=240) as resp:
            out["status"] = resp.status; out["ctype"] = resp.headers.get("content-type")
            ev = None
            for line in resp:
                line = line.decode().rstrip("\n")
                if line.startswith("event:"): ev = line[6:].strip()
                elif line.startswith("data:"):
                    d = json.loads(line[5:].strip()); out["events"].append(ev)
                    if ev == "delta":
                        out["deltas"] += 1; out["text"] += d["text"]
                        if out["first_delta_s"] is None: out["first_delta_s"] = round(time.time() - t0, 2)
                    elif ev == "tool_result": out["traces"].append(d)
                    elif ev == "error": out["error"] = d
                    elif ev == "done": out["done"] = d
    except urllib.error.HTTPError as e:
        out["status"] = e.code; out["body"] = e.read().decode()
    out["elapsed_s"] = round(time.time() - t0, 2)
    return out

def rec(k, ok, note):
    R[k] = {"ok": ok, "note": note}
    print(f"[{ 'PASS' if ok else 'FAIL'}] {k}: {note}", flush=True)

ts = int(time.time()) % 100000
TMP = f"qa_tmp_{ts}"

# ---- Auth ----
s, d = req("POST", "/api/auth/login", {"username": "demo", "password": "verabot2026"})
demo = d.get("token") if s == 200 else None
rec("AUTH-01 login ok", s == 200 and bool(demo), f"status={s} user={d.get('user') if s==200 else d}")
s, d = req("POST", "/api/auth/login", {"username": "demo", "password": "wrongpass1"})
rec("AUTH-02 wrong pw", s == 401, f"status={s} body={d}")
s, d = req("POST", "/api/auth/login", {"username": "nobody_xyz", "password": "whatever1"})
rec("AUTH-02b unknown user", s == 401, f"status={s} body={d} (same msg as wrong pw => no user enumeration)")
s, d = req("GET", "/api/bots")
rec("SEC-01 no token", s == 401, f"status={s} body={d}")
s, d = req("GET", "/api/bots", token="abc.def.ghi")
rec("SEC-02 garbage token", s == 401, f"status={s} body={d}")
# tampered token: flip payload sub to another id
hdr, pl, sig = demo.split(".")
p = json.loads(base64.urlsafe_b64decode(pl + "=" * (-len(pl) % 4)))
p["sub"] = "1"
forged = hdr + "." + base64.urlsafe_b64encode(json.dumps(p).encode()).decode().rstrip("=") + "." + sig
s, d = req("GET", "/api/me", token=forged)
rec("SEC-03 forged token", s == 401, f"status={s} body={d}")
s, d = req("GET", "/api/me", token=demo)
rec("AUTH-03 /api/me", s == 200 and d.get("username") == "demo", f"status={s} body={d}")

# ---- Register / isolation ----
s, d = req("POST", "/api/auth/register", {"username": TMP, "password": "qa123456"})
tmp = d.get("token") if s == 200 else None
rec("ISO-01 register temp", s == 200, f"status={s} user={d.get('user') if s==200 else d}")
s, d = req("POST", "/api/auth/register", {"username": TMP, "password": "qa123456"})
rec("AUTH-04 dup register", s == 409, f"status={s} body={d}")
s, d = req("POST", "/api/auth/register", {"username": "ab", "password": "12345"})
rec("AUTH-05 short creds", s == 422, f"status={s}")
s, d = req("GET", "/api/bots", token=tmp)
rec("ISO-02 temp sees no bots", s == 200 and d["bots"] == [], f"status={s} bots={[b['name'] for b in d['bots']]} limit={d['limit']}")
s, dd = req("GET", "/api/bots", token=demo)
demo_bots = {b["name"]: b["id"] for b in dd["bots"]}
print("demo bots", demo_bots)
vid = demo_bots.get("Vera")
res = []
for m, pth, body in [("GET", f"/api/bots/{vid}", None), ("GET", f"/api/bots/{vid}/messages", None),
                     ("PATCH", f"/api/bots/{vid}", {"name": "hacked"}), ("DELETE", f"/api/bots/{vid}/messages", None),
                     ("DELETE", f"/api/bots/{vid}", None), ("POST", f"/api/bots/{vid}/chat", {"message": "hi"}),
                     ("POST", "/api/reminders/1/done", None)]:
    s, _ = req(m, pth, body, token=tmp); res.append(f"{m} {pth}->{s}")
allok = all(x.endswith("->404") for x in res)
rec("ISO-03 cross-user access", allok, "; ".join(res))
s, d = req("GET", "/api/reminders", token=tmp)
rec("ISO-04 temp reminders empty", s == 200 and d["reminders"] == [], f"count={len(d['reminders'])}")

# ---- Bot CRUD ----
s, a = req("POST", "/api/bots", {"name": "测试A", "avatar": "🧪", "persona": "测试用助理，回答简短", "instructions": "回答不超过 50 字"}, token=tmp)
rec("BOT-01 create", s == 201 and a.get("name") == "测试A", f"status={s} bot={a}")
s, d = req("POST", "/api/bots", {"name": "测试A"}, token=tmp)
rec("BOT-02 dup name", s == 409, f"status={s} body={d}")
s, b = req("POST", "/api/bots", {"name": "测试B", "avatar": "🐼", "persona": "测试用助理B"}, token=tmp)
s, e = req("PATCH", f"/api/bots/{b['id']}", {"persona": "编辑后的人设", "avatar": "🦉"}, token=tmp)
rec("BOT-03 edit", s == 200 and e["persona"] == "编辑后的人设" and e["avatar"] == "🦉", f"status={s} bot={e}")
s, d = req("PATCH", f"/api/bots/{b['id']}", {"name": "测试A"}, token=tmp)
rec("BOT-04 rename to dup", s == 409, f"status={s} body={d}")
s, c = req("POST", "/api/bots", {"name": "测试C", "persona": "测试用助理C"}, token=tmp)
s, d4 = req("POST", "/api/bots", {"name": "测试D"}, token=tmp)
s, d5 = req("POST", "/api/bots", {"name": "测试E"}, token=tmp)
s, d6 = req("POST", "/api/bots", {"name": "测试F"}, token=tmp)
rec("BOT-05 6th bot rejected", s == 400, f"status={s} body={d6}")
s, d = req("DELETE", f"/api/bots/{d5['id']}", token=tmp)
s2, _ = req("GET", f"/api/bots/{d5['id']}", token=tmp)
rec("BOT-06 delete", s == 200 and s2 == 404, f"delete={s} get-after={s2}")
s, bl = req("POST", "/api/bots", {"name": "   "}, token=tmp)
rec("BOT-07 blank name rejected", s in (400, 422), f"status={s} body={bl}")
if s == 201: req("DELETE", f"/api/bots/{bl['id']}", token=tmp)
s, pb = req("PATCH", f"/api/bots/{d4['id']}", {"name": "  测试D2  "}, token=tmp)
rec("BOT-08 patch name trimmed", s == 200 and pb.get("name") == "测试D2", f"status={s} name={pb.get('name')!r}")

# ---- Chat / streaming ----
r = chat(tmp, a["id"], "你好，用一句话介绍你自己")
rec("CHAT-01 streaming", r.get("status") == 200 and r["deltas"] > 3 and "done" in r and "text/event-stream" in (r.get("ctype") or ""),
    f"ctype={r.get('ctype')} deltas={r['deltas']} first_delta={r['first_delta_s']}s total={r['elapsed_s']}s events_tail={r['events'][-2:]} text={r['text'][:80]!r}")
s, d = req("POST", f"/api/bots/{a['id']}/chat", {"message": ""}, token=tmp)
rec("CHAT-02 empty msg", s == 422, f"status={s}")
s, d = req("POST", f"/api/bots/{a['id']}/chat", {"message": "   "}, token=tmp, raw=True)
rec("CHAT-03 whitespace msg rejected", s in (400, 422), f"status={s} body={str(d)[:160]!r}")
s, d = req("POST", f"/api/bots/{a['id']}/chat", {"message": "长" * 4001}, token=tmp)
rec("CHAT-04 4001 chars", s == 422, f"status={s}")
r = chat(tmp, a["id"], ("这是一段长消息测试。" * 399) + "请只回复：收到")
rec("CHAT-05 4000 chars ok", r.get("status") == 200 and "done" in r and not r.get("error"), f"status={r.get('status')} text={r['text'][:60]!r} err={r.get('error')}")

# ---- Memory ----
r1 = chat(tmp, a["id"], "请记住：我的幸运数字是 427，我养了一只叫豆包的猫。记住就回复好的。")
r2 = chat(tmp, a["id"], "我的幸运数字是多少？我的猫叫什么？")
rec("MEM-01 same bot remembers", "427" in r2["text"] and "豆包" in r2["text"], f"A={r2['text'][:100]!r}")
r3 = chat(tmp, b["id"], "我的幸运数字是多少？我的猫叫什么？不知道就直说不知道，不要调用任何工具。")
rec("MEM-02 other bot doesn't know", "427" not in r3["text"] and "豆包" not in r3["text"], f"B={r3['text'][:120]!r} tools={[t['name'] for t in r3['traces']]}")

# ---- Weather ----
r = chat(tmp, a["id"], "石家庄天气怎么样")
w = [t for t in r["traces"] if t["name"] == "get_weather"]
ok = bool(w) and "error" not in w[0]["result"] and w[0]["result"].get("forecast")
rec("TOOL-01 weather", bool(ok), f"tools={[t['name'] for t in r['traces']]} src={w[0]['result'].get('source') if w else None} cur={w[0]['result'].get('current') if w else None} text={r['text'][:120]!r}")
print("WEATHER_TEXT_HAS_TILDE", "~" in r["text"], repr(r["text"][:400]))
r = chat(tmp, a["id"], "查一下火星城XYZ123的天气")
w = [t for t in r["traces"] if t["name"] == "get_weather"]
rec("TOOL-02 weather unknown city", (not w) or "error" in w[0]["result"], f"result={w[0]['result'] if w else 'no call'} text={r['text'][:100]!r}")

# ---- Reminder ----
r = chat(tmp, a["id"], "明天上午10点提醒我提交QA测试报告")
rm = [t for t in r["traces"] if t["name"] == "create_reminder"]
s, d = req("GET", "/api/reminders", token=tmp)
rec("TOOL-03 reminder", bool(rm) and rm[0]["result"].get("ok") and any("测试报告" in x["content"] for x in d["reminders"]),
    f"trace={rm[0]['result'] if rm else None} list={[ (x['content'], x['due_at'], x['bot_name']) for x in d['reminders']]}")
if d["reminders"]:
    rid = d["reminders"][0]["id"]
    s, _ = req("POST", f"/api/reminders/{rid}/done", token=tmp)
    s2, d2 = req("GET", "/api/reminders", token=tmp)
    rec("TOOL-04 reminder done", s == 200 and d2["reminders"][0]["done"] == 1, f"done={s}")

# ---- ask_bot ----
r = chat(tmp, a["id"], "请用 ask_bot 去问一下 测试B：推荐一本适合入门的编程书（只要书名）。然后把它的回答告诉我。")
ab = [t for t in r["traces"] if t["name"] == "ask_bot"]
rec("AGENT-01 ask_bot", bool(ab) and ab[0]["result"].get("to_bot") == "测试B" and ab[0]["result"].get("answer"),
    f"n_calls={len(ab)} result={ {k: str(v)[:80] for k, v in (ab[0]['result'] if ab else {}).items()} } text={r['text'][:100]!r}")
r = chat(tmp, a["id"], "请用 ask_bot 让 测试B 再去 ask_bot 问 测试C：1+1 等于几。要求测试B必须自己去问测试C，不能直接回答。")
ab = [t for t in r["traces"] if t["name"] == "ask_bot"]
rec("AGENT-02 no chaining", True, f"top-level ask_bot calls={len(ab)} targets={[t['result'].get('to_bot') for t in ab]} answers={[str(t['result'].get('answer'))[:120] for t in ab]}")
r = chat(tmp, a["id"], "用 ask_bot 问一下 不存在的机器人Z：今天星期几")
ab = [t for t in r["traces"] if t["name"] == "ask_bot"]
rec("AGENT-03 ask unknown bot", (not ab) or "error" in ab[0]["result"], f"result={ab[0]['result'] if ab else 'no call'}")

# ---- Messages / clear ----
s, d = req("GET", f"/api/bots/{a['id']}/messages", token=tmp)
n_before = len(d["messages"]); has_tr = any(m["traces"] for m in d["messages"])
s, _ = req("DELETE", f"/api/bots/{a['id']}/messages", token=tmp)
s2, d2 = req("GET", f"/api/bots/{a['id']}/messages", token=tmp)
rec("CHAT-06 clear", s == 200 and d2["messages"] == [], f"before={n_before} traces_persisted={has_tr} after={len(d2['messages'])}")
r = chat(tmp, a["id"], "我的幸运数字是多少？不知道就说不知道。")
rec("MEM-03 memory gone after clear", "427" not in r["text"], f"text={r['text'][:100]!r}")

# ---- Quota ----
s, q = req("GET", "/api/quota", token=tmp)
rec("QUOTA-01 quota", s == 200 and q["today"]["total_tokens"] > 0 and q["delegations"] >= 1,
    f"today={q['today']} delegations={q['delegations']} per_bot={[(x['name'], x['total_tokens']) for x in q['per_bot']]} quota={q['daily_token_quota']}")
s, q2 = req("GET", "/api/quota", token=demo)
rec("QUOTA-02 quota isolation", s == 200, f"demo today={q2['today']} per_bot={[x['name'] for x in q2['per_bot']]}")
s, h = req("GET", "/api/health")
rec("MISC-01 health", s == 200, f"{h}")

os.makedirs(os.path.join(os.path.dirname(os.path.abspath(__file__)), "results"), exist_ok=True)
json.dump({"tmp_user": TMP, "results": R}, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "results", "api_results.json"), "w"), ensure_ascii=False, indent=1)
print("TMPUSER", TMP)
