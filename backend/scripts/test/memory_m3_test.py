#!/usr/bin/env python3
"""记忆成长 M3 后端回归。临时 SQLite，不访问生产数据。"""
import os
import sqlite3
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

TMP = tempfile.mkdtemp(prefix="vb_m3_")
os.environ["VERABOT_DB"] = str(Path(TMP) / "m3.db")
os.environ["VERABOT_DATA_DIR"] = TMP
os.environ["VERABOT_MEMORY_JOBS"] = "0"
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from verabot import db  # noqa: E402
from verabot.db import suggestion_store  # noqa: E402


class SuggestionStoreTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        db.init_db()
        with db.tx() as c:
            c.execute("INSERT INTO users(username,password_hash,created_at) VALUES ('m3a','x',?)", ("2026-10-07",))
            cls.uid = c.execute("SELECT id FROM users WHERE username='m3a'").fetchone()[0]
            c.execute("INSERT INTO users(username,password_hash,created_at) VALUES ('m3b','x',?)", ("2026-10-07",))
            cls.uid2 = c.execute("SELECT id FROM users WHERE username='m3b'").fetchone()[0]
            c.execute("INSERT INTO bots(user_id,name,created_at) VALUES (?, 'A', '2026-10-07')", (cls.uid,))
            cls.bot = c.execute("SELECT id FROM bots WHERE user_id=?", (cls.uid,)).fetchone()[0]

    def setUp(self):
        with db.tx() as c:
            c.execute("DELETE FROM suggestions")

    def create(self, user_id=None, dedupe="routine:daily", expires=None):
        return suggestion_store.create_or_get_active(
            user_id=user_id or self.uid, bot_id=self.bot, kind="routine_reminder",
            dedupe_key=dedupe, payload={"title": "每周整理"},
            expires_at=expires or (datetime.now(timezone.utc) + timedelta(days=30)).isoformat(),
        )

    def test_suggestion_schema_v15_is_idempotent(self):
        db.init_db()
        with db.tx() as c:
            version = c.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()[0]
            names = {r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            indexes = {r[1] for r in c.execute("PRAGMA index_list(suggestions)")}
        self.assertEqual(version, "15")
        self.assertIn("suggestions", names)
        self.assertTrue(any("dedupe" in name for name in indexes))

    def test_suggestion_state_changes_are_idempotent(self):
        suggestion = self.create()
        first = suggestion_store.decide(self.uid, suggestion["id"], "accepted")
        second = suggestion_store.decide(self.uid, suggestion["id"], "accepted")
        self.assertEqual(first["status"], "accepted")
        self.assertEqual(second["status"], "accepted")

    def test_suggestion_queries_are_user_scoped(self):
        suggestion = self.create()
        self.assertEqual(suggestion_store.list_pending(self.uid, self.bot)[0]["id"], suggestion["id"])
        self.assertEqual(suggestion_store.list_pending(self.uid2, self.bot), [])
        self.assertIsNone(suggestion_store.decide(self.uid2, suggestion["id"], "dismissed"))

    def test_suggestion_dismissal_cooldown(self):
        suggestion = self.create()
        suggestion_store.decide(self.uid, suggestion["id"], "dismissed")
        again = self.create()
        self.assertEqual(again["id"], suggestion["id"])
        self.assertEqual(again["status"], "dismissed")


if __name__ == "__main__":
    unittest.main(verbosity=2)
