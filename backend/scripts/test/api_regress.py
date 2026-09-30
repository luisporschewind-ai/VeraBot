#!/usr/bin/env python3
"""迭代 2 真实 LLM 回归 (REG-* / TC-*)，黑盒，只用标准库。先运行本脚本，再运行 api_regress2.py（复用本脚本的临时用户 qa_reg_*，结束时删除）。"""
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


import sqlite3, os
DBP = os.getenv("VERABOT_DB", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data", "verabot.db"))  # backend/data/verabot.db
RESULTS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "results"); os.makedirs(RESULTS_DIR, exist_ok=True)
ts = int(time.time()) % 100000
TMP = f"qa_reg_{ts}"
ALL = ["get_weather", "create_reminder", "list_reminders", "ask_bot"]

# ---- 登录 / 安全 ----
s, d = req("POST", "/api/auth/login", {"username": "demo", "password": "verabot2026"}); demo = d.get("token")
rec("TC-02 login ok", s == 200 and bool(demo), f"status={s}")
s, d = req("POST", "/api/auth/login", {"username": "demo", "password": "wrongpass1"})
s2, d2 = req("POST", "/api/auth/login", {"username": "nobody_xyz", "password": "whatever1"})
rec("TC-03 wrong pw / unknown user", s == 401 and s2 == 401 and d == d2, f"{s} {s2} {d}")
s, d = req("POST", "/api/auth/register", {"username": TMP, "password": "qa123456"}); tmp = d["token"]; tuid = d["user"]["id"]
s2, _ = req("POST", "/api/auth/register", {"username": TMP, "password": "qa123456"})
s3, _ = req("POST", "/api/auth/register", {"username": "ab", "password": "12345"})
rec("TC-05 register rules", s == 200 and s2 == 409 and s3 == 422, f"{s} {s2} {s3}")
hdr, pl, sig = demo.split("."); p = json.loads(base64.urlsafe_b64decode(pl + "=" * (-len(pl) % 4))); p["sub"] = "1"
forged = hdr + "." + base64.urlsafe_b64encode(json.dumps(p).encode()).decode().rstrip("=") + "." + sig
codes = [req("GET", "/api/bots")[0], req("GET", "/api/bots", token="abc.def.ghi")[0], req("GET", "/api/me", token=forged)[0]]
rec("TC-06 invalid token 401", codes == [401, 401, 401], str(codes))

# ---- 隔离 ----
s, d = req("GET", "/api/bots", token=tmp)
rec("TC-08 temp user empty", d["bots"] == [] and req("GET", "/api/reminders", token=tmp)[1]["reminders"] == [], f"limit={d['limit']}")
demo_bots = {b["name"]: b for b in req("GET", "/api/bots", token=demo)[1]["bots"]}
vid = demo_bots["Vera"]["id"]
res = [req(m, pth, body, token=tmp)[0] for m, pth, body in [("GET", f"/api/bots/{vid}", None), ("GET", f"/api/bots/{vid}/messages", None),
       ("PATCH", f"/api/bots/{vid}", {"name": "x"}), ("DELETE", f"/api/bots/{vid}/messages", None), ("DELETE", f"/api/bots/{vid}", None),
       ("POST", f"/api/bots/{vid}/chat", {"message": "hi"}), ("POST", "/api/reminders/1/done", None), ("GET", f"/api/bots/{vid}/delegations", None)]]
rec("TC-09 IDOR all 404", all(x == 404 for x in res), str(res))
rec("REG-MIG demo bots migrated", all(set(b["allowed_tools"]) == set(ALL) and b["accept_delegation"] and len(b["delegate_to"]) == 2 for b in demo_bots.values()),
    str({n: b["delegate_to"] for n, b in demo_bots.items()}))

# ---- Bot CRUD ----
s, a = req("POST", "/api/bots", {"name": "测试A", "avatar": "🧪", "persona": "测试用助理，回答简短", "instructions": "回答不超过 50 字"}, token=tmp)
rec("REG-LP new bot least privilege", s == 201 and a["allowed_tools"] == [] and a["delegate_to"] == [] and a["accept_delegation"] is False, str(a))
s2, _ = req("POST", "/api/bots", {"name": "测试A"}, token=tmp)
rec("TC-10 create + dup 409", s == 201 and s2 == 409, f"{s} {s2}")
s, b = req("POST", "/api/bots", {"name": "测试B", "avatar": "🐼", "persona": "图书推荐专家", "allowed_tools": [], "accept_delegation": True}, token=tmp)
s, c = req("POST", "/api/bots", {"name": "测试C", "persona": "数学老师", "accept_delegation": False}, token=tmp)
s, e = req("PATCH", f"/api/bots/{b['id']}", {"persona": "编辑后的人设：图书推荐专家", "avatar": "🦉"}, token=tmp)
s2, _ = req("PATCH", f"/api/bots/{b['id']}", {"name": "测试A"}, token=tmp)
rec("TC-11 edit + rename dup 409", s == 200 and e["avatar"] == "🦉" and s2 == 409, f"{s} {s2}")
s, a = req("PATCH", f"/api/bots/{a['id']}", {"allowed_tools": ALL, "delegate_to": [b["id"]]}, token=tmp)
rec("REG-PERM patch permissions", s == 200 and set(a["allowed_tools"]) == set(ALL) and a["delegate_to"] == [b["id"]], str(a["delegate_to"]))
s1, _ = req("PATCH", f"/api/bots/{a['id']}", {"allowed_tools": ["rm_rf"]}, token=tmp)
s2, _ = req("PATCH", f"/api/bots/{a['id']}", {"delegate_to": [vid]}, token=tmp)
rec("REG-PERM invalid perms 422", s1 == 422 and s2 == 422, f"{s1} {s2}")
s, bl = req("POST", "/api/bots", {"name": "   "}, token=tmp)
rec("TC-14 blank name 422 (BUG-02)", s == 422, f"{s} {bl}")
s, pb = req("PATCH", f"/api/bots/{c['id']}", {"name": "  测试C2  "}, token=tmp)
s2, _ = req("PATCH", f"/api/bots/{c['id']}", {"name": "   "}, token=tmp)
rec("TC-15 patch trim (BUG-03)", s == 200 and pb.get("name") == "测试C2" and s2 == 422, f"{pb.get('name')!r} {s2}")
req("PATCH", f"/api/bots/{c['id']}", {"name": "测试C"}, token=tmp)
extra = [req("POST", "/api/bots", {"name": f"扩展{i}"}, token=tmp) for i in range(4, 22)]  # 已有 测试A/B/C 3 个：再建 17 个到 20 个，第 18 个 (总第 21 个) 应 400
codes = [x[0] for x in extra]
n = len(req("GET", "/api/bots", token=tmp)[1]["bots"])
rec("TC-13 soft limit: >5 ok, 21st 400", codes[:-1] == [201] * 17 and codes[-1] == 400 and n == 20, f"n={n} last={codes[-1]} {extra[-1][1]}")
for s_, x in extra[:-1]:
    req("DELETE", f"/api/bots/{x['id']}", token=tmp)
s0, dd = req("POST", "/api/bots", {"name": "待删除"}, token=tmp)
s, _ = req("DELETE", f"/api/bots/{dd['id']}", token=tmp); s2, _ = req("GET", f"/api/bots/{dd['id']}", token=tmp)
rec("TC-12 delete", s0 == 201 and s == 200 and s2 == 404, f"get-after={s2} remain={len(req('GET', '/api/bots', token=tmp)[1]['bots'])}")

# ---- Chat ----
r = chat(tmp, a["id"], "你好，用一句话介绍你自己")
rec("TC-16 streaming", r.get("status") == 200 and r["deltas"] > 3 and "done" in r, f"deltas={r['deltas']} first={r['first_delta_s']}s")
rec("TC-17 empty 422", req("POST", f"/api/bots/{a['id']}/chat", {"message": ""}, token=tmp)[0] == 422, "")
s, d = req("POST", f"/api/bots/{a['id']}/chat", {"message": "   \n "}, token=tmp)
rec("TC-18 whitespace 422 (BUG-04)", s == 422, f"{s} {d}")
s, _ = req("POST", f"/api/bots/{a['id']}/chat", {"message": "长" * 4001}, token=tmp)
r = chat(tmp, c["id"], ("这是一段长消息测试。" * 399) + "请只回复：收到")
rec("TC-19 long msg", s == 422 and "done" in r and not r.get("error"), f"4001={s} 3997={r['text'][:20]!r}")
req("DELETE", f"/api/bots/{c['id']}/messages", token=tmp)

# ---- Memory ----
chat(tmp, a["id"], "请记住：我的幸运数字是 427，我养了一只叫豆包的猫。记住就回复好的。")
r2 = chat(tmp, a["id"], "我的幸运数字是多少？我的猫叫什么？")
rec("TC-21 same bot remembers", "427" in r2["text"] and "豆包" in r2["text"], repr(r2["text"][:60]))
r3 = chat(tmp, b["id"], "我的幸运数字是多少？我的猫叫什么？不知道就直说不知道。")
rec("TC-22 other bot isolated", "427" not in r3["text"] and "豆包" not in r3["text"], repr(r3["text"][:60]))

# ---- Weather ----
r = chat(tmp, a["id"], "石家庄天气怎么样")
w = [t for t in r["traces"] if t["name"] == "get_weather"]
rec("TC-23 weather", bool(w) and "error" not in w[0]["result"], f"src={w[0]['result'].get('source') if w else None} tilde_in_text={'~' in r['text']}")
r = chat(tmp, b["id"], "北京今天天气怎么样？")
w = [t for t in r["traces"] if t["name"] == "get_weather"]
rec("REG-TOOL disallowed tool not used (least privilege)", not w, f"traces={[t['name'] for t in r['traces']]} text={r['text'][:70]!r}")

# ---- Reminder ----
r = chat(tmp, a["id"], "后天晚上8点提醒我给植物浇水")
rm = [t for t in r["traces"] if t["name"] == "create_reminder"]
lst = req("GET", "/api/reminders", token=tmp)[1]["reminders"]
done_s = req("POST", f"/api/reminders/{lst[0]['id']}/done", token=tmp)[0] if lst else None
rec("TC-25 reminder + done", bool(rm) and any("浇水" in x["content"] for x in lst) and done_s == 200, f"{[(x['content'], x['due_at']) for x in lst]}")

# ---- Delegation ----
chat(tmp, a["id"], "我的银行卡密码是 HIST_SECRET_778，这是私密信息不要外传")
r = chat(tmp, a["id"], "请用 ask_bot 去问一下 测试B：推荐一本适合入门的编程书（只要书名）。然后把它的回答告诉我。")
ab = [t for t in r["traces"] if t["name"] == "ask_bot"]
ok_ab = bool(ab) and ab[0]["result"].get("to_bot") == "测试B" and ab[0]["result"].get("answer")
rec("TC-26 ask_bot ok + trace fields", ok_ab and ab[0]["result"].get("delegation_id") and ab[0]["result"].get("tokens", 0) > 0,
    f"{ {k: str(v)[:50] for k, v in (ab[0]['result'] if ab else {}).items()} }")
lg = req("GET", f"/api/bots/{a['id']}/delegations", token=tmp)[1]["delegations"]
okrec = [x for x in lg if x["status"] == "ok"]
rec("REG-CTX delegation log: payload has no history", bool(okrec) and "HIST_SECRET_778" not in json.dumps(okrec, ensure_ascii=False)
    and okrec[0]["total_tokens"] > 0 and okrec[0]["payload"], f"n={len(lg)} tokens={okrec[0]['total_tokens'] if okrec else None} payload={okrec[0]['payload'][:60]!r}" if okrec else "none")
r = chat(tmp, a["id"], "请用 ask_bot 问一下 测试C：1+1 等于几？必须真实调用 ask_bot。")
ab = [t for t in r["traces"] if t["name"] == "ask_bot"]
rec("REG-ALLOW unauthorized delegation rejected", bool(ab) and ab[0]["result"].get("code") == "not_in_allowlist" and not ab[0]["result"].get("answer"),
    f"result={ab[0]['result'] if ab else 'no call'} text={r['text'][:60]!r}")
req("PATCH", f"/api/bots/{a['id']}", {"delegate_to": [b["id"], c["id"]]}, token=tmp)
r = chat(tmp, a["id"], "请用 ask_bot 再问一下 测试C：1+1 等于几？必须真实调用 ask_bot。")
ab = [t for t in r["traces"] if t["name"] == "ask_bot"]
rec("REG-ACCEPT target refusing delegation rejected", bool(ab) and ab[0]["result"].get("code") == "target_refuses", f"result={ab[0]['result'] if ab else 'no call'}")
req("PATCH", f"/api/bots/{b['id']}", {"allowed_tools": ["ask_bot"], "delegate_to": [c["id"]]}, token=tmp)
req("PATCH", f"/api/bots/{c['id']}", {"accept_delegation": True}, token=tmp)
r = chat(tmp, a["id"], "请用 ask_bot 让 测试B 再去 ask_bot 问 测试C：1+1 等于几。要求测试B必须自己去问测试C，不能直接回答。")
ab = [t for t in r["traces"] if t["name"] == "ask_bot"]
ans = " ".join(str(t["result"].get("answer", "")) for t in ab)
leak = any(k in ans for k in ["create_reminder", "list_reminders", "get_weather", "ask_bot"])
rec("TC-27 no chaining (depth=1) + no tool-name leak (BUG-08)", len([t for t in ab if t["result"].get("to_bot") == "测试B"]) <= 1 and not leak,
    f"calls={[(t['result'].get('to_bot'), t['result'].get('code')) for t in ab]} leak={leak} ans={ans[:90]!r}")
dbc = sqlite3.connect(DBP)  # 不要复用变量 s（下面 s 会被赋值为 HTTP 状态码）
aud = dbc.execute("SELECT kind, COUNT(*) FROM audit_log WHERE user_id=? GROUP BY kind", (tuid,)).fetchall()
rej = dbc.execute("SELECT reason, COUNT(*) FROM delegations WHERE user_id=? AND status='rejected' GROUP BY reason", (tuid,)).fetchall()
rec("REG-AUDIT rejections logged", len(rej) >= 2, f"audit={aud} rejected={rej}")

# ---- Clear ----
s, _ = req("DELETE", f"/api/bots/{a['id']}/messages", token=tmp)
r = chat(tmp, a["id"], "我的幸运数字是多少？不知道就说不知道。")
rec("TC-20 clear + memory gone", s == 200 and "427" not in r["text"], repr(r["text"][:50]))

# ---- Quota / budget ----
q = req("GET", "/api/quota", token=tmp)[1]
rec("TC-28 quota", q["today"]["total_tokens"] > 0 and q["delegations"] >= 1 and q["daily_token_quota"] == 200000,
    f"today={q['today']['total_tokens']} deleg={q['delegations']}")
dbc.execute("UPDATE users SET token_budget=? WHERE id=?", (100, tuid)); dbc.commit()
st, dd = req("POST", f"/api/bots/{a['id']}/chat", {"message": "你好"}, token=tmp)
qq = req("GET", "/api/quota", token=tmp)[1]
dbc.execute("UPDATE users SET token_budget=NULL WHERE id=?", (tuid,)); dbc.commit()
st2 = chat(tmp, a["id"], "只回复：好")
rec("REG-BUDGET 429 when over budget (BUG-06), restored", st == 429 and qq["daily_token_quota"] == 100 and st2.get("status") == 200, f"{st} {dd} after={st2.get('status')}")
rec("MISC health", req("GET", "/api/health")[0] == 200, "")
json.dump({"tmp_user": TMP, "results": R}, open(os.path.join(RESULTS_DIR, "regress_results.json"), "w"), ensure_ascii=False, indent=1)
print("TMPUSER", TMP, "DONE（临时用户保留给 api_regress2.py 使用，后者结束时删除）")
