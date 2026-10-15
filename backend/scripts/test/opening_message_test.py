#!/usr/bin/env python3
"""Bot 开场词模板：迁移、mock 生成、ensure、称呼解析、PATCH 清空。

临时 SQLite，不消耗真实 Token。运行（在 backend/ 下）：
    uv run python scripts/test/opening_message_test.py
"""
from __future__ import annotations

import asyncio
import json
import os
import sqlite3
import sys
import tempfile
from pathlib import Path
from unittest.mock import AsyncMock

TMP = tempfile.mkdtemp(prefix="vb_opening_")
DB = str(Path(TMP) / "t.db")
os.environ["VERABOT_DB"] = DB
os.environ["VERABOT_DATA_DIR"] = TMP
os.environ.setdefault("DEEPSEEK_API_KEY", "test-not-used")

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from verabot import db  # noqa: E402
from verabot.services.opening import address as opening_address  # noqa: E402
from verabot.services.opening import generate as opening_generate  # noqa: E402

RESULTS = []


def check(cid, name, ok, note=""):
    RESULTS.append((cid, name, bool(ok), note))
    print(f"[{'PASS' if ok else 'FAIL'}] {cid} {name} {note}", flush=True)


db.init_db()
db.init_db()

con = sqlite3.connect(DB)
ver = con.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()[0]
bot_cols = {r[1] for r in con.execute("PRAGMA table_info(bots)")}
con.close()
check(
    "OPEN-01",
    "schema v32 含 opening_templates 列且幂等",
    ver == "32" and db.SCHEMA_VERSION == 32 and "opening_templates" in bot_cols,
    f"ver={ver} SCHEMA_VERSION={db.SCHEMA_VERSION}",
)


async def _fake_complete(messages, max_tokens=800):
    payload = {
        "version": 1,
        "first_meeting": ["{greeting}，我是{bot_name}。{invite}", "石家庄天气怎么样"],
        "returning": ["{greeting}，{address}。{day_note}{invite}"],
        "invite": "有事交给我。",
    }
    return json.dumps(payload, ensure_ascii=False), {"total_tokens": 10}


async def run_async_cases():
    templates = await opening_generate.generate_for_bot(
        "大管家", "贴心管家", "", complete_json=_fake_complete,
    )
    check(
        "OPEN-02",
        "mock 生成解析成功且过滤城市硬编码条",
        templates is not None
        and templates["invite"] == "有事交给我。"
        and len(templates["first_meeting"]) == 1
        and "石家庄" not in json.dumps(templates, ensure_ascii=False),
        f"templates={templates}",
    )

    from fastapi.testclient import TestClient
    from verabot.main import app
    from verabot.services import memory as memory_svc

    cli = TestClient(app)

    def reg(username):
        r = cli.post("/api/auth/register", json={"username": username, "password": "pw123456"})
        body = r.json()
        return {"Authorization": "Bearer " + body["token"]}, body["user"]

    H, user = reg("opener_user")
    uid = user["id"]

    created = cli.post("/api/bots", json={"name": "大管家", "persona": "贴心管家"}, headers=H)
    check(
        "OPEN-03",
        "创建 Bot 返回 opening_templates 字段（可为 null）",
        created.status_code == 201 and "opening_templates" in created.json(),
        f"status={created.status_code} body_keys={sorted(created.json())}",
    )
    bid = created.json()["id"]

    bot = db.get_bot(uid, bid)
    result = await opening_generate.ensure_templates(
        {"id": uid}, bot, complete_json=_fake_complete, generate=True,
    )
    check(
        "OPEN-04",
        "ensure 首次生成并落库",
        result["generated"] is True and result["opening_templates"] is not None,
    )
    bot2 = db.get_bot(uid, bid)
    again = await opening_generate.ensure_templates(
        {"id": uid}, bot2,
        complete_json=AsyncMock(side_effect=AssertionError("should not call")),
        generate=True,
    )
    check(
        "OPEN-05",
        "ensure 幂等不再调模型",
        again["generated"] is False and again["opening_templates"] is not None,
    )

    async def boom(*a, **k):
        raise RuntimeError("model down")

    opening_generate.clear_templates(uid, bid)
    failed = await opening_generate.ensure_templates(
        {"id": uid}, db.get_bot(uid, bid), complete_json=boom, generate=True,
    )
    check(
        "OPEN-06",
        "生成失败不落库，返回 null 供客户端兜底",
        failed["opening_templates"] is None and db.get_bot(uid, bid).get("opening_templates") is None,
    )

    # 称呼记忆（敏感住址在写入层已被拒绝，这里测解析层拦截）
    memory_svc.create(uid, content="称呼用户为Boss", type="profile", scope="global", bot_id=None)
    addr = opening_address.preferred_address(uid, bid)
    blocked = opening_address._parse("家庭住址在某某路1号")
    check(
        "OPEN-07",
        "称呼解析取 Boss 且拒绝敏感住址文案",
        addr == "Boss" and blocked is None,
        f"addr={addr} blocked={blocked}",
    )

    opening_generate.save_templates(uid, bid, opening_generate.builtin_fallback("大管家", "管家"))
    patch = cli.patch(f"/api/bots/{bid}", json={"persona": "更贴身的管家"}, headers=H)
    bot_after = db.get_bot(uid, bid)
    check(
        "OPEN-08",
        "PATCH persona 清空 opening_templates",
        patch.status_code == 200 and bot_after.get("opening_templates") is None,
        f"status={patch.status_code} templates={bot_after.get('opening_templates')}",
    )

    opening_generate.save_templates(uid, bid, opening_generate.builtin_fallback("大管家"))
    from verabot.services.bots import public_bot
    pub = public_bot(db.get_bot(uid, bid))
    check(
        "OPEN-09",
        "public_bot 含 opening_templates 与 opening_address",
        isinstance(pub.get("opening_templates"), dict) and pub.get("opening_address") == "Boss",
        f"addr={pub.get('opening_address')}",
    )

    # 服务层已覆盖 ensure；此处再验 parse / 兜底人设。
    bad = opening_generate.parse_templates({"first_meeting": [], "returning": ["x"]})
    good = opening_generate.parse_templates(opening_generate.builtin_fallback("调查员", "查事"))
    check(
        "OPEN-10",
        "parse 拒绝空列表；内置兜底对人设生效",
        bad is None and "查" in good["invite"],
        f"invite={good['invite']}",
    )


asyncio.run(run_async_cases())

failed = [r for r in RESULTS if not r[2]]
print(f"\n{len(RESULTS) - len(failed)}/{len(RESULTS)} passed", flush=True)
sys.exit(1 if failed else 0)
