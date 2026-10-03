#!/usr/bin/env python3
"""SSE `status` 事件（召回记忆 + 委派内部进度）的确定性测试与前后端契约（STAT-01~08）。
临时 SQLite + mock LLM，不消耗 Token。运行（在 backend/ 下）：uv run python scripts/test/status_event_test.py
"""
import json, os, re, sys, tempfile
from pathlib import Path

TMP = tempfile.mkdtemp(prefix="vb_stat_")
os.environ["VERABOT_DB"] = str(Path(TMP) / "t.db")
os.environ["VERABOT_DATA_DIR"] = TMP
os.environ["VERABOT_MAX_DELEGATION_DEPTH"] = "2"   # 允许两跳，验证 depth / parent_id 沿委派树传递
os.environ.setdefault("DEEPSEEK_API_KEY", "test-not-used")
ROOT = Path(__file__).resolve().parents[2]          # backend/
sys.path.insert(0, str(ROOT))

from verabot import db  # noqa: E402
from verabot.services import llm  # noqa: E402
from verabot.agents import runtime  # noqa: E402

RESULTS = []
def check(cid, name, ok, note=""):
    RESULTS.append((cid, name, bool(ok), note)); print(f"[{'PASS' if ok else 'FAIL'}] {cid} {name} {note}", flush=True)

db.init_db()
from fastapi.testclient import TestClient  # noqa: E402
from verabot.main import app  # noqa: E402
cli = TestClient(app)
r = cli.post("/api/auth/register", json={"username": "stat_u", "password": "pw123456"})
H = {"Authorization": "Bearer " + r.json()["token"]}
A = cli.post("/api/bots", json={"name": "A"}, headers=H).json()
B = cli.post("/api/bots", json={"name": "B"}, headers=H).json()
C = cli.post("/api/bots", json={"name": "C"}, headers=H).json()
cli.patch(f"/api/bots/{A['id']}", json={"allowed_tools": ["ask_bot"], "delegate_to": [B["id"]]}, headers=H)
cli.patch(f"/api/bots/{B['id']}", json={"allowed_tools": ["ask_bot"], "delegate_to": [C["id"]], "accept_delegation": True}, headers=H)
cli.patch(f"/api/bots/{C['id']}", json={"accept_delegation": True}, headers=H)

# ---------- mock LLM ----------
PLAN = []
async def fake_stream(messages, tools):
    step = PLAN.pop(0) if PLAN else "好的"
    if isinstance(step, str):
        yield "delta", step
    else:
        yield "tool_calls", [{"id": "outer1", "name": n, "arguments": json.dumps(a, ensure_ascii=False)} for n, a in step]
    yield "usage", {"total_tokens": 3}
    yield "finish", "stop"
DPLAN = []
async def fake_complete(messages, tools):
    step = DPLAN.pop(0) if DPLAN else "子答复"
    if isinstance(step, str):
        return {"content": step, "_finish_reason": "stop"}, {"total_tokens": 2}
    return {"content": None, "tool_calls": [{"id": "inner1", "type": "function", "function": {
        "name": step[0], "arguments": json.dumps(step[1], ensure_ascii=False)}}]}, {"total_tokens": 2}
llm.stream_chat, llm.complete = fake_stream, fake_complete

def sse(bot_id, plan, dplan=()):
    PLAN[:], DPLAN[:] = list(plan), list(dplan)
    evs, cur = [], None
    for line in cli.post(f"/api/bots/{bot_id}/chat", json={"message": "问一下"}, headers=H).text.splitlines():
        if line.startswith("event:"):
            cur = line[6:].strip()
        elif line.startswith("data:"):
            evs.append((cur, json.loads(line[5:].strip())))
    return evs

# 外层 A → ask_bot(B)；B 先 ask_bot(C)，C 直接答；B 再答；A 最后出字
evs = sse(A["id"], [[("ask_bot", {"bot_name": "B", "question": "q"})], "最终回答"],
          [("ask_bot", {"bot_name": "C", "question": "q2"}), "C 的答复", "B 的答复"])
names = [e for e, _ in evs]
stats = [d for e, d in evs if e == "status"]

check("STAT-01", "首个事件是 status recalling (depth 0，本 Bot，无 tool / parent_id)",
      evs and evs[0] == ("status", {"phase": "recalling", "depth": 0, "bot_name": "A", "tool": None, "parent_id": None}), str(evs[:1]))

inner = [(d["phase"], d["depth"], d["bot_name"], d["tool"], d["parent_id"]) for d in stats[1:]]
expect = [("thinking", 1, "B", None, "outer1"), ("tool", 1, "B", "ask_bot", "outer1"),
          ("thinking", 2, "C", None, "outer1"), ("thinking", 1, "B", None, "outer1")]
check("STAT-02", "委派内部进度按顺序推送，depth / bot_name / tool 正确，parent_id 均为外层 tool_start id", inner == expect, str(inner))

i_start, i_result = names.index("tool_start"), names.index("tool_result")
between = [e for e in names[i_start + 1:i_result]]
check("STAT-03", "委派进度全部位于外层 tool_start 与 tool_result 之间；done 仍是最后一个事件",
      between == ["status"] * 4 and names[-1] == "done" and names.count("done") == 1, str(names))

check("STAT-04", "每个 status payload 恰好 5 个键，phase ∈ STATUS_PHASES",
      all(tuple(d) == runtime.STATUS_KEYS and d["phase"] in runtime.STATUS_PHASES for d in stats), str(stats))

tr = next(d for e, d in evs if e == "tool_result")
dn = next(d for e, d in evs if e == "done")
check("STAT-05", "向后兼容：tool_result / done 字段不变；委派答复照常返回",
      set(tr) == {"id", "name", "args", "result"} and tr["result"].get("answer") == "B 的答复"
      and {"message_id", "usage", "memory_ids"} <= set(dn), f"{tr} {dn}")

msgs = cli.get(f"/api/bots/{A['id']}/messages", headers=H).json()["messages"]
traces = msgs[-1].get("traces") or []
check("STAT-06", "status 不写入 messages.traces (只保存工具 trace)",
      [t["name"] for t in traces] == ["ask_bot"] and all("phase" not in t for t in traces), str(traces)[:200])

cli.patch("/api/memory/settings", json={"enabled": False}, headers=H)
evs2 = sse(A["id"], ["你好"])
check("STAT-07", "用户关闭记忆 → 不推送 recalling；无工具时无 status",
      [e for e, _ in evs2] == ["delta", "done"], str(evs2))
cli.patch("/api/memory/settings", json={"enabled": True}, headers=H)

# ---------- STAT-08 契约：与 iOS VeraBotCore ChatStatus 对照 ----------
swift = (ROOT.parent / "frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore/ExecutionState.swift").read_text()
cs = swift[swift.index("public struct ChatStatus"):]
keys_block = cs[cs.index("enum CodingKeys"):]
keys_block = keys_block[:keys_block.index("}")]
ios_keys = set()
for name, raw in re.findall(r"case (\w+)(?: = \"([a-z_]+)\")?", keys_block):
    ios_keys.add(raw or name)
phase_block = cs[cs.index("public enum Phase"):]
phase_block = phase_block[:phase_block.index("}")]
ios_phases = set(re.findall(r"case (\w+)", phase_block))
check("STAT-08", "契约：status 键 = iOS ChatStatus CodingKeys；phase 取值 = iOS ChatStatus.Phase",
      ios_keys == set(runtime.STATUS_KEYS) and ios_phases == set(runtime.STATUS_PHASES),
      f"ios_keys={sorted(ios_keys)} ios_phases={sorted(ios_phases)}")

passed = sum(ok for *_, ok, _ in RESULTS)
print(f"\nSUMMARY {passed}/{len(RESULTS)} passed")
sys.exit(0 if passed == len(RESULTS) else 1)
