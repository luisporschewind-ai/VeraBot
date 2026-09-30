#!/usr/bin/env python3
"""VeraBot v0.1 API test runner (black-box, stdlib only)."""
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

TMP = "qa_tmp_43016"
s, d = req("POST", "/api/auth/login", {"username": TMP, "password": "qa123456"}); tmp = d["token"]
s, d = req("POST", "/api/auth/login", {"username": "demo", "password": "verabot2026"}); demo = d["token"]
bots = {x["name"]: x for x in req("GET", "/api/bots", token=tmp)[1]["bots"]}
print("tmp bots", list(bots))
a, b = bots["测试A"], bots["测试B"]

c = bots["测试C"]
r = chat(tmp, c["id"], "后天晚上8点提醒我给植物浇水")
rm = [t for t in r["traces"] if t["name"] == "create_reminder"]
s, d = req("GET", "/api/reminders", token=tmp)
rec("TOOL-03 reminder (retry, fresh bot)", bool(rm) and any("浇水" in x["content"] for x in d["reminders"]),
    f"trace={rm[0]['result'] if rm else None} list={[(x['content'], x['due_at'], x['bot_name'], x['done']) for x in d['reminders']]} text={r['text'][:80]!r}")
for i in range(3):
    r = chat(tmp, a["id"], "我的幸运数字是多少？不知道就说不知道。")
    print("NOREPLY-REPRO", i, r.get("status"), r["deltas"], repr(r["text"][:80]), r["events"][-3:], r.get("error"), r.get("done"), flush=True)
r = chat(tmp, c["id"], "   ")
print("WS-MSG", r["status"], repr(r["text"][:100]))
s, d = req("GET", f"/api/bots/{c['id']}/messages", token=tmp)
print("WS-STORED", [(m["role"], m["content"][:40]) for m in d["messages"]][-2:])
