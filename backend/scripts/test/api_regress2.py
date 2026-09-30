#!/usr/bin/env python3
"""api_regress.py 的续跑：预算 429、软上限 20、422 文案。复用最新的临时用户 qa_reg_*，结束时删除该用户（--keep 保留）。"""
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
con = sqlite3.connect(DBP)
TMP, tuid = con.execute("SELECT username, id FROM users WHERE username LIKE 'qa_reg_%' ORDER BY id DESC").fetchone()
tmp = req("POST", "/api/auth/login", {"username": TMP, "password": "qa123456"})[1]["token"]
bots = req("GET", "/api/bots", token=tmp)[1]["bots"]; a = [b for b in bots if b["name"] == "测试A"][0]
con.execute("UPDATE users SET token_budget=? WHERE id=?", (100, tuid)); con.commit()
st, dd = req("POST", f"/api/bots/{a['id']}/chat", {"message": "你好"}, token=tmp)
qq = req("GET", "/api/quota", token=tmp)[1]
con.execute("UPDATE users SET token_budget=NULL WHERE id=?", (tuid,)); con.commit()
r = chat(tmp, a["id"], "只回复：好")
rec("REG-BUDGET 429 over budget (BUG-06) + restore", st == 429 and qq["daily_token_quota"] == 100 and r.get("status") == 200,
    f"{st} {dd} quota_shown={qq['daily_token_quota']} after_restore={r.get('status')}")
n0 = len(bots)
codes = [req("POST", "/api/bots", {"name": f"扩展X{i}"}, token=tmp)[0] for i in range(25 - n0)]
n = len(req("GET", "/api/bots", token=tmp)[1]["bots"])
s21, d21 = req("POST", "/api/bots", {"name": "第21个"}, token=tmp)
rec("TC-13 soft limit 20: >5 ok, 21st 400", n == 20 and s21 == 400 and codes.count(201) == 20 - n0, f"start={n0} n={n} 21st={s21} {d21}")
s, d = req("POST", "/api/bots", {"name": "   "}, token=tmp)
rec("REG-422 clean validation message", s == 422 and d["detail"][0]["msg"] == "Bot 名称不能为空", str(d))
for b in req("GET", "/api/bots", token=tmp)[1]["bots"]:
    if b["name"].startswith("扩展"):
        req("DELETE", f"/api/bots/{b['id']}", token=tmp)
json.dump(R, open(os.path.join(RESULTS_DIR, "regress_results2.json"), "w"), ensure_ascii=False, indent=1)
if "--keep" not in sys.argv:  # 清理临时用户（外键级联删除其 Bot / 消息 / 提醒 / 委派 / 用量 / 审计）
    con.execute("PRAGMA foreign_keys=ON")
    n = con.execute("DELETE FROM users WHERE id=?", (tuid,)).rowcount; con.commit()
    print(f"cleaned up {n} temp user ({TMP})")
print("DONE")
