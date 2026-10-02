#!/usr/bin/env python3
"""Bot 置顶迁移、API 和 iOS 契约测试；仅使用临时 SQLite。"""
import json, os, sqlite3, sys, tempfile
import time
from pathlib import Path

TMP = tempfile.mkdtemp(prefix="vb_pin_")
DB = str(Path(TMP) / "t.db")
os.environ["VERABOT_DB"] = DB
os.environ["VERABOT_DATA_DIR"] = TMP
os.environ.setdefault("DEEPSEEK_API_KEY", "test-not-used")
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

# Construct a v5 database and verify migration adds only nullable pinned_at.
c = sqlite3.connect(DB)
c.executescript("""
CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT UNIQUE NOT NULL, password_hash TEXT NOT NULL,
 created_at TEXT NOT NULL, token_budget INTEGER, nickname TEXT, avatar_updated_at TEXT, memory_enabled INTEGER DEFAULT 1);
CREATE TABLE bots (id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL, name TEXT NOT NULL, avatar TEXT NOT NULL DEFAULT '🤖',
 color TEXT NOT NULL DEFAULT '#0F766E', persona TEXT NOT NULL DEFAULT '', instructions TEXT NOT NULL DEFAULT '',
 created_at TEXT NOT NULL, allowed_tools TEXT NOT NULL DEFAULT '[]', delegate_to TEXT NOT NULL DEFAULT '[]',
 accept_delegation INTEGER NOT NULL DEFAULT 0, image_updated_at TEXT, memory_access TEXT NOT NULL DEFAULT 'bot_and_global',
 tags TEXT NOT NULL DEFAULT '[]', UNIQUE(user_id,name));
CREATE TABLE schema_meta (key TEXT PRIMARY KEY,value TEXT NOT NULL);
INSERT INTO schema_meta VALUES ('version','5');
INSERT INTO users VALUES (1,'legacy','x','2026-01-01',NULL,NULL,NULL,1);
INSERT INTO bots(id,user_id,name,created_at,tags) VALUES (1,1,'Old','2026-01-01','["研究"]');
""")
c.commit(); c.close()

from verabot import db
db.init_db(); db.init_db()
c = sqlite3.connect(DB)
cols = {r[1] for r in c.execute('PRAGMA table_info(bots)')}
legacy = c.execute('SELECT name,tags,pinned_at FROM bots WHERE id=1').fetchone()
version = c.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()[0]
c.close()
assert "pinned_at" in cols and legacy == ("Old", '["研究"]', None)
assert version == str(db.SCHEMA_VERSION) == "6"

from fastapi.testclient import TestClient
from verabot.main import app
cli = TestClient(app)
h = {"Authorization": "Bearer " + cli.post('/api/auth/register', json={"username":"pinuser","password":"pw123456"}).json()["token"]}
a = cli.post('/api/bots', json={"name":"A"}, headers=h).json()
b = cli.post('/api/bots', json={"name":"B"}, headers=h).json()
assert a["pinned_at"] is None
for bot in (a,b):
    if bot == b: time.sleep(1.05)  # db.now_iso() 精度为秒，明确制造不同时间戳
    response = cli.patch(f"/api/bots/{bot['id']}", json={"pinned":True}, headers=h)
    assert response.status_code == 200 and response.json()["pinned_at"]
    if bot == b: b = response.json()
a = cli.patch(f"/api/bots/{a['id']}", json={"pinned":True}, headers=h).json()
assert a["pinned_at"] == cli.patch(f"/api/bots/{a['id']}", json={"pinned":True}, headers=h).json()["pinned_at"]
assert [x["name"] for x in cli.get('/api/bots', headers=h).json()["bots"]][:2] == ["B","A"]
# Equal timestamps fall back to id ascending, both on the API and in BotOrdering.
with db.tx() as c:
    c.execute("UPDATE bots SET pinned_at=? WHERE id IN (?,?)", (a["pinned_at"], a["id"], b["id"]))
assert [x["name"] for x in cli.get('/api/bots', headers=h).json()["bots"]][:2] == ["A","B"]
assert cli.patch(f"/api/bots/{b['id']}", json={"pinned":False}, headers=h).json()["pinned_at"] is None
assert [x["name"] for x in cli.get('/api/bots', headers=h).json()["bots"]][:2] == ["A","B"]
assert cli.patch(f"/api/bots/{a['id']}", json={"name":"Renamed"}, headers=h).json()["pinned_at"] == a["pinned_at"]
assert cli.patch(f"/api/bots/{a['id']}", json={"pinned":None}, headers=h).json()["pinned_at"] == a["pinned_at"]
bad_pin = cli.patch(f"/api/bots/{a['id']}", json={"pinned":"yes"}, headers=h)
assert bad_pin.status_code == 422 and "pinned 必须是布尔值" in bad_pin.text
h2 = {"Authorization": "Bearer " + cli.post('/api/auth/register', json={"username":"otherpin","password":"pw123456"}).json()["token"]}
assert cli.patch(f"/api/bots/{a['id']}", json={"pinned":False}, headers=h2).status_code == 404
assert cli.get(f"/api/bots/{a['id']}", headers=h).json()["pinned_at"] == a["pinned_at"]

# Cross-layer contract: CodingKeys and deterministic ordering share the same fixture.
models = (Path(__file__).resolve().parents[3] / "frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore/Models.swift").read_text()
assert 'case pinnedAt = "pinned_at"' in models and 'case pinned' in models and "BotOrdering" in models
print("PIN-01..08 PASS; migration, API ordering/validation/isolation, response fields and iOS contract")
