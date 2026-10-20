"""Task 1: real SQLite transactions for Drift Bottle storage.

Run from backend/:  .venv/bin/python scripts/test/drift_bottle_store_test.py
Uses a temporary database only.
"""
import json
import sqlite3
import threading
import unittest
from pathlib import Path
from uuid import uuid4

from scheduled_task_test_support import DBTest, db, NOW
from verabot.core import ratelimit
from verabot.db import drift_bottle_store as store
from verabot.db.migrations import v039_drift_bottle as migration
from verabot.services.drift_bottle import service
from verabot.services.drift_bottle.contracts import (
    ContributionInput, DrawRequest, ReleaseRequest, CreateBottleRequest, BottleError,
)

NOW_S = NOW.timestamp()


class DriftStoreTests(DBTest):
    def setUp(self):
        super().setUp()
        ratelimit.reset()
        with db.tx() as c:
            for uid in (3, 4):
                c.execute("INSERT INTO users(id,username,password_hash,created_at) VALUES (?,?,?,?)",
                          (uid, f"user{uid}", "test", NOW.isoformat()))
                c.execute("INSERT INTO bots(id,user_id,name,created_at,allowed_tools) VALUES (?,?,?,?,?)",
                          (uid, uid, f"bot{uid}", NOW.isoformat(), "[]"))

    def bot(self, uid):
        with db.tx() as c:
            return dict(c.execute("SELECT * FROM bots WHERE id=?", (uid,)).fetchone())

    def make_bottle(self, uid=3, text="从南边搬来以后，我还在找一家合适的早餐店。"):
        with db.tx(immediate=True) as c:
            return store.create_bottle_tx(c, uid, self.bot(uid), text, "owner", NOW_S)[0]

    def draw(self, uid=4, bot_id=None):
        with db.tx(immediate=True) as c:
            return store.draw_tx(c, uid, self.bot(bot_id or uid), NOW_S)

    def test_concurrent_draw_has_one_winner(self):
        bottle = self.make_bottle()
        barrier = threading.Barrier(2)
        results = {}

        def worker(uid):
            barrier.wait()
            with db.tx(immediate=True) as c:
                results[uid] = store.draw_tx(c, uid, self.bot(uid), NOW_S)

        threads = [threading.Thread(target=worker, args=(uid,)) for uid in (3, 4)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        winners = [uid for uid, (eid, _) in results.items() if eid is not None]
        self.assertEqual(len(winners), 1, results)
        with db.tx() as c:
            self.assertEqual(c.execute("SELECT COUNT(*) FROM drift_bottle_encounters WHERE bottle_id=?",
                                       (bottle,)).fetchone()[0], 1)
            self.assertEqual(c.execute("SELECT COUNT(*) FROM drift_bottle_reads WHERE bottle_id=?",
                                       (bottle,)).fetchone()[0], 1)

    def test_same_account_resumes_one_encounter(self):
        self.make_bottle()
        first, resumed = self.draw(4)
        self.assertFalse(resumed)
        second, resumed = self.draw(4)
        self.assertTrue(resumed)
        self.assertEqual(first, second)
        self.assertEqual(len(self.draw(4)), 2)
        with db.tx() as c:
            self.assertEqual(c.execute("SELECT COUNT(*) FROM drift_bottle_encounters WHERE user_id=4")
                             .fetchone()[0], 1)

    def test_replay_release_adds_one_contribution(self):
        self.make_bottle()
        with db.tx() as c:
            encounter = store.encounter_row(c, 4, self.draw(4)[0])
            bot = self.bot(4)
        body = ReleaseRequest(request_id=str(uuid4()), lease_token=encounter["lease_token"],
                              expected_version=1,
                              contribution=ContributionInput(body="谢谢你把早餐店也写进信里。",
                                                             authorship="owner"))
        first = service.release(4, encounter["id"], body, NOW_S + 10)
        second = service.release(4, encounter["id"], body, NOW_S + 11)
        self.assertEqual(first["record"]["id"], second["record"]["id"])
        self.assertEqual(first["operation"]["request_id"], second["operation"]["request_id"])
        with db.tx() as c:
            self.assertEqual(c.execute("SELECT public_count FROM drift_bottles").fetchone()[0], 2)
            self.assertEqual(c.execute("SELECT COUNT(*) FROM drift_bottle_contributions WHERE kind='message'")
                             .fetchone()[0], 1)
            self.assertEqual(c.execute("SELECT COUNT(*) FROM drift_bottle_encounters WHERE ended_at IS NOT NULL")
                             .fetchone()[0], 1)
            self.assertEqual(c.execute("SELECT COUNT(*) FROM drift_bottle_memories").fetchone()[0], 1)

    def test_request_id_payload_conflict(self):
        self.make_bottle()
        with db.tx() as c:
            encounter = store.encounter_row(c, 4, self.draw(4)[0])
        request_id = str(uuid4())
        one = ReleaseRequest(request_id=request_id, lease_token=encounter["lease_token"],
                             expected_version=1, contribution=None)
        service.release(4, encounter["id"], one, NOW_S + 10)
        two = ReleaseRequest(request_id=request_id, lease_token=encounter["lease_token"],
                             expected_version=1,
                             contribution=ContributionInput(body="另一句话", authorship="owner"))
        with self.assertRaises(BottleError) as error:
            service.release(4, encounter["id"], two, NOW_S + 11)
        self.assertEqual(error.exception.code, "request_conflict")
        with db.tx() as c:
            self.assertEqual(c.execute("SELECT COUNT(*) FROM drift_bottle_contributions WHERE kind='message'")
                             .fetchone()[0], 0)

    def test_migration_idempotent_preserves_existing_rows_and_foreign_keys(self):
        with db.tx() as c:
            before = c.execute("SELECT COUNT(*) FROM users").fetchone()[0]
            for _ in range(2):
                migration.migrate(c, 39)
            self.assertEqual(c.execute("PRAGMA integrity_check").fetchone()[0], "ok")
            self.assertEqual(c.execute("PRAGMA foreign_key_check").fetchall(), [])
            self.assertEqual(c.execute("SELECT COUNT(*) FROM users").fetchone()[0], before)
            self.assertEqual(c.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()[0], "39")

    def test_bot_delete_keeps_public_snapshot_and_private_history(self):
        self.make_bottle()
        encounter_id, _ = self.draw(4)
        with db.tx() as c:
            c.execute("DELETE FROM bots WHERE id=4")
        with db.tx() as c:
            encounter = store.encounter_row(c, 4, encounter_id)
            self.assertIsNone(encounter["bot_id"])
            self.assertEqual(encounter["bot_name"], "bot4")
            self.assertEqual(c.execute("PRAGMA foreign_key_check").fetchall(), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
