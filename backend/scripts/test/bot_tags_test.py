#!/usr/bin/env python3
"""Bot 标签（tags，schema v5）确定性测试。

临时 SQLite，不消耗 Token、不触碰正式数据库。覆盖：
v4 → v5 幂等迁移、创建 / 列表 / 详情 / 更新、校验（trim、去空、去重、上限 3 个 / 4 字、控制字符）、用户隔离、
存量超限数据收敛（TAG-09）、iOS 规则契约（TAG-10）。

运行（在 backend/ 下）：uv run python scripts/test/bot_tags_test.py
"""
import json
import os
import sqlite3
import sys
import tempfile
from pathlib import Path

TMP = tempfile.mkdtemp(prefix="vb_tags_")
DB = str(Path(TMP) / "t.db")
os.environ["VERABOT_DB"] = DB
os.environ["VERABOT_DATA_DIR"] = TMP
os.environ.setdefault("DEEPSEEK_API_KEY", "test-not-used")

# ---------- 1. 先摆一个 schema v4 的库（有记忆列，没有 tags） ----------
V4 = """
CREATE TABLE users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  created_at TEXT NOT NULL,
  token_budget INTEGER,
  nickname TEXT,
  avatar_updated_at TEXT,
  memory_enabled INTEGER NOT NULL DEFAULT 1
);
CREATE TABLE bots (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  avatar TEXT NOT NULL DEFAULT '🤖',
  color TEXT NOT NULL DEFAULT '#0F766E',
  persona TEXT NOT NULL DEFAULT '',
  instructions TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  allowed_tools TEXT NOT NULL DEFAULT '[]',
  delegate_to TEXT NOT NULL DEFAULT '[]',
  accept_delegation INTEGER NOT NULL DEFAULT 0,
  image_updated_at TEXT,
  memory_access TEXT NOT NULL DEFAULT 'bot_and_global',
  UNIQUE(user_id, name)
);
CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
"""
con = sqlite3.connect(DB)
con.executescript(V4)
con.execute("INSERT INTO schema_meta(key,value) VALUES ('version','4')")
con.execute("INSERT INTO users(id,username,password_hash,created_at,nickname) VALUES (1,'legacy_tag','x','2026-01-01','老王')")
con.execute(
    "INSERT INTO bots(id,user_id,name,avatar,created_at,allowed_tools,delegate_to,accept_delegation,"
    "image_updated_at,memory_access) VALUES (1,1,'OldBot','🐼','2026-01-01','[\"get_weather\"]','[2]',0,'t1','bot')"
)
con.commit()
con.close()

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))  # backend/

from verabot import db  # noqa: E402

RESULTS = []


def check(cid, name, ok, note=""):
    RESULTS.append((cid, name, bool(ok), note))
    print(f"[{'PASS' if ok else 'FAIL'}] {cid} {name} {note}", flush=True)


db.init_db()
db.init_db()  # 幂等
con = sqlite3.connect(DB)
ver = con.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()[0]
bot_cols = {r[1] for r in con.execute("PRAGMA table_info(bots)")}
legacy = con.execute(
    "SELECT name, allowed_tools, delegate_to, image_updated_at, memory_access, tags FROM bots WHERE id=1"
).fetchone()
con.execute("UPDATE bots SET tags=? WHERE id=1", ('["研究"]',))
con.commit()
con.close()
db.init_db()  # 已有标签不能被第二次迁移清掉
kept = sqlite3.connect(DB).execute("SELECT tags FROM bots WHERE id=1").fetchone()[0]
check(
    "TAG-01",
    "v4→v5 幂等：出现 tags 且默认 []；存量权限 / 记忆授权 / 头像不变；再跑一次不覆盖已写入的标签",
    ver == "5" and db.SCHEMA_VERSION == 5 and "tags" in bot_cols
    and legacy == ("OldBot", '["get_weather"]', "[2]", "t1", "bot", "[]")
    and json.loads(kept) == ["研究"],
    f"ver={ver} legacy={legacy} kept={kept}",
)

from fastapi.testclient import TestClient  # noqa: E402

from verabot.main import app  # noqa: E402

cli = TestClient(app)


def reg(username):
    r = cli.post("/api/auth/register", json={"username": username, "password": "pw123456"})
    body = r.json()
    return {"Authorization": "Bearer " + body["token"]}, body["user"]


def err_text(resp):
    d = resp.json().get("detail")
    if isinstance(d, list):
        return " ".join((x.get("msg") if isinstance(x, dict) else str(x)) or "" for x in d)
    return "" if d is None else str(d)


H, _ = reg("alice_tag")
H2, _ = reg("bob_tag")

bare = cli.post("/api/bots", json={"name": "无标签"}, headers=H)
check(
    "TAG-02",
    "创建时不传 tags：列表与详情都是 []，且仍是最小权限",
    bare.status_code == 201 and bare.json().get("tags") == []
    and bare.json().get("allowed_tools") == [] and bare.json().get("accept_delegation") is False
    and cli.get(f"/api/bots/{bare.json()['id']}", headers=H).json().get("tags") == [],
    str(bare.json()),
)

messy = cli.post("/api/bots", json={
    "name": "有标签",
    "tags": ["  研究 ", "", "研究", "写作", "  ", "写作", "\u3000天气\u3000"],
}, headers=H)
created = messy.json()
listed = next(b for b in cli.get("/api/bots", headers=H).json()["bots"] if b["id"] == created["id"])
detail = cli.get(f"/api/bots/{created['id']}", headers=H).json()
check(
    "TAG-03",
    "创建时 trim、丢掉空白和重复，保留首次出现的顺序；列表与详情一致",
    messy.status_code == 201 and created.get("tags") == ["研究", "写作", "天气"]
    and listed.get("tags") == ["研究", "写作", "天气"] and detail.get("tags") == ["研究", "写作", "天气"],
    str(created.get("tags")),
)

renamed = cli.patch(f"/api/bots/{created['id']}", json={"name": "有标签2"}, headers=H)
check(
    "TAG-04",
    "更新其他字段时省略 tags，标签保持不变",
    renamed.status_code == 200 and renamed.json().get("name") == "有标签2"
    and renamed.json().get("tags") == ["研究", "写作", "天气"],
    str(renamed.json().get("tags")),
)
cleared = cli.patch(f"/api/bots/{created['id']}", json={"tags": []}, headers=H)
replaced = cli.patch(f"/api/bots/{created['id']}", json={"tags": [" 日程 ", "日程", "笔记"]}, headers=H)
check(
    "TAG-05",
    "tags: [] 清空；再次 PATCH 整表替换，并同样做 trim / 去重",
    cleared.status_code == 200 and cleared.json().get("tags") == []
    and replaced.status_code == 200 and replaced.json().get("tags") == ["日程", "笔记"],
    f"clear={cleared.json().get('tags')} replaced={replaced.json().get('tags')}",
)

three = ["搜索", "查询", "调研"]
ok_three = cli.post("/api/bots", json={"name": "三个", "tags": three}, headers=H)
ok_len = cli.post("/api/bots", json={"name": "四字", "tags": ["一二三四"]}, headers=H)
too_many = cli.post("/api/bots", json={"name": "四个", "tags": [f"标{i}" for i in range(4)]}, headers=H)
too_long = cli.patch(f"/api/bots/{created['id']}", json={"tags": ["一二三四五"]}, headers=H)
ctrl = cli.patch(f"/api/bots/{created['id']}", json={"tags": ["研\n究"]}, headers=H)
ctrl_del = cli.patch(f"/api/bots/{created['id']}", json={"tags": ["a\x7fb"]}, headers=H)
not_list = cli.post("/api/bots", json={"name": "不是列表", "tags": "研究"}, headers=H)
not_str = cli.patch(f"/api/bots/{created['id']}", json={"tags": [1]}, headers=H)
null_tags = cli.post("/api/bots", json={"name": "空标签", "tags": None}, headers=H)
# 超限 / 非法不能改掉已保存的标签
still = cli.get(f"/api/bots/{created['id']}", headers=H).json()
check(
    "TAG-06",
    "恰好 3 个、恰好 4 字通过；4 个 / 5 字、控制字符、非列表、非文字、null → 422 中文，且不写入",
    ok_three.status_code == 201 and ok_three.json().get("tags") == three
    and ok_len.status_code == 201 and ok_len.json().get("tags") == ["一二三四"]
    and too_many.status_code == 422 and err_text(too_many) == "每个 Bot 最多 3 个标签"
    and too_long.status_code == 422 and err_text(too_long) == "每个标签最多 4 个字"
    and ctrl.status_code == 422 and err_text(ctrl) == "标签不能包含控制字符"
    and ctrl_del.status_code == 422 and err_text(ctrl_del) == "标签不能包含控制字符"
    and not_list.status_code == 422 and err_text(not_list) == "标签必须是列表"
    and not_str.status_code == 422 and err_text(not_str) == "标签必须是文字"
    and null_tags.status_code == 422 and err_text(null_tags) == "标签必须是列表"
    and "Value error" not in err_text(too_many) and still.get("tags") == ["日程", "笔记"],
    " | ".join(err_text(r) for r in (too_many, too_long, ctrl, not_list, not_str, null_tags)),
)

stolen = cli.patch(f"/api/bots/{created['id']}", json={"tags": ["偷看"]}, headers=H2)
stolen_get = cli.get(f"/api/bots/{created['id']}", headers=H2)
bob_list = cli.get("/api/bots", headers=H2).json()["bots"]
mine = cli.get(f"/api/bots/{created['id']}", headers=H).json()
check(
    "TAG-07",
    "他人 PATCH / GET 该 Bot → 404；自己的标签不变；对方列表里没有这个 Bot",
    stolen.status_code == 404 and stolen_get.status_code == 404
    and mine.get("tags") == ["日程", "笔记"]
    and all(b["id"] != created["id"] for b in bob_list),
    f"patch={stolen.status_code} get={stolen_get.status_code}",
)

dups_only = cli.post("/api/bots", json={"name": "重复加空白", "tags": ["", "  ", "工作", "工作", ""]}, headers=H)
check(
    "TAG-08",
    "只含空白和重复时收成一个标签；省略与显式空列表都得到 []",
    dups_only.status_code == 201 and dups_only.json().get("tags") == ["工作"]
    and bare.json().get("tags") == [],
    str(dups_only.json().get("tags")),
)

# ---------- TAG-09 存量超限数据：启动时收敛 + 读取时收敛；收敛后 PATCH 其他字段不再 422 ----------
legacy_tags = ["一二三四五六", "研究", "  ", "一二三四", "写作", "天气", "日程"]
con = sqlite3.connect(DB)
con.execute("UPDATE bots SET tags=? WHERE id=?", (json.dumps(legacy_tags, ensure_ascii=False), created["id"]))
con.commit()
read_before = cli.get(f"/api/bots/{created['id']}", headers=H).json().get("tags")   # 读取路径收敛（尚未重启）
db.init_db()                                                                           # 启动时收敛（幂等）
stored = json.loads(con.execute("SELECT tags FROM bots WHERE id=?", (created["id"],)).fetchone()[0])
db.init_db()
stored2 = json.loads(con.execute("SELECT tags FROM bots WHERE id=?", (created["id"],)).fetchone()[0])
con.close()
patched = cli.patch(f"/api/bots/{created['id']}", json={"name": "收敛后", "tags": stored}, headers=H)
expect9 = ["一二三四", "研究", "写作"]   # 截到 4 字后「一二三四五六」与「一二三四」重复，去重；只留前 3 个
check(
    "TAG-09",
    "存量超限标签：读取与启动时都收敛为前 3 个、每个截到 4 字、去重；幂等；之后带原标签 PATCH 成功",
    read_before == expect9 and stored == expect9 and stored2 == expect9
    and patched.status_code == 200 and patched.json().get("tags") == expect9,
    f"read={read_before} stored={stored} patch={patched.status_code}",
)

# ---------- TAG-10 前后端契约：iOS BotTagRules 的上限与错误文案与后端一致；Bot JSON 含 tags ----------
import re  # noqa: E402
from verabot.core import tags as tag_rules  # noqa: E402
swift = (Path(__file__).resolve().parents[3] / "frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore/BotTags.swift").read_text()
ios_count = int(re.search(r"maxCount\s*=\s*(\d+)", swift).group(1))
ios_len = int(re.search(r"maxLength\s*=\s*(\d+)", swift).group(1))
msgs = ["每个 Bot 最多 \\(maxCount) 个标签", "每个标签最多 \\(maxLength) 个字", "标签不能包含控制字符"]
check(
    "TAG-10",
    "契约：iOS maxCount / maxLength = 后端 MAX_BOT_TAGS / MAX_TAG_CHARS (3 / 4)；错误文案同源；Bot JSON 含 tags 数组",
    ios_count == tag_rules.MAX_BOT_TAGS == 3 and ios_len == tag_rules.MAX_TAG_CHARS == 4
    and all(m in swift for m in msgs)
    and isinstance(cli.get("/api/bots", headers=H).json()["bots"][0].get("tags"), list),
    f"ios=({ios_count},{ios_len}) backend=({tag_rules.MAX_BOT_TAGS},{tag_rules.MAX_TAG_CHARS})",
)

p = sum(1 for r in RESULTS if r[2])
print(f"\nSUMMARY {p}/{len(RESULTS)} passed")
sys.exit(0 if p == len(RESULTS) else 1)
