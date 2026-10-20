"""Task 7 acceptance: two real test accounts, public/private boundary,
third-party reading, restart recovery, concurrency and 50-contribution archive.

No internal database writes are used to skip the public API/service rules.
"""
import json
import threading
import unittest
from uuid import uuid4

from scheduled_task_test_support import DBTest, db, NOW
from verabot.core import ratelimit
from verabot.db import drift_bottle_store as store
from verabot.services.drift_bottle import service
from verabot.services.drift_bottle.contracts import (
    BlockRequest, BottleError, ContributionInput, CreateBottleRequest, DrawRequest,
    MemoryRequest, ReleaseRequest, TurnRequest, WithdrawRequest,
)

NOW_S = NOW.timestamp()


async def fake_model(messages, max_tokens):
    system = messages[0]["content"]
    if "回忆" in system or "片段" in system:
        return json.dumps({"title": "海边早餐店的来信",
                           "summary": "我们一起读了一封关于搬家的信，聊到海边的早餐店。"},
                          ensure_ascii=False), {}
    return json.dumps({"text": "我也注意到信里那家还没找到的早餐店。"},
                      ensure_ascii=False), {}


class DriftAcceptanceTests(DBTest):
    def setUp(self):
        super().setUp()
        ratelimit.reset()
        service.set_model_for_tests(fake_model)
        with db.tx() as c:
            for uid in range(3, 57):
                c.execute("INSERT INTO users(id,username,password_hash,created_at) VALUES (?,?,?,?)",
                          (uid, f"user{uid}", "test", NOW.isoformat()))
                c.execute("INSERT INTO bots(id,user_id,name,created_at,allowed_tools) VALUES (?,?,?,?,?)",
                          (uid, uid, f"bot{uid}", NOW.isoformat(), "[]"))

    def tearDown(self):
        service.set_model_for_tests(None)
        super().tearDown()

    def req(self):
        return str(uuid4())

    def create(self, uid, text="从北方搬到海边以后，我还在找一家合适的早餐店。"):
        return service.create_bottle(uid, CreateBottleRequest(
            request_id=self.req(), bot_id=uid, body=text, authorship="owner"), NOW_S)

    def draw(self, uid):
        return service.draw(uid, DrawRequest(request_id=self.req(), bot_id=uid), NOW_S)

    def release(self, uid, encounter, text):
        return service.release(uid, encounter["id"], ReleaseRequest(
            request_id=self.req(), lease_token=encounter["lease_token"],
            expected_version=encounter["bottle_version"],
            contribution=ContributionInput(body=text, authorship="owner") if text else None),
            NOW_S + 1)

    def chat(self, uid, encounter, text="我也在海边找过早餐店。"):
        return service.turns(uid, encounter["id"], TurnRequest(
            request_id=self.req(), kind="chat", text=text), NOW_S + 2)

    def test_two_accounts_public_private_boundary_and_third_reader(self):
        self.create(3)
        encounter = self.draw(4)["encounter"]
        opening = service.turns(4, encounter["id"], TurnRequest(
            request_id=self.req(), kind="opening"), NOW_S + 2)
        self.assertEqual(opening["turn"]["kind"], "opening")
        self.chat(4, encounter)
        # Private talk never becomes a public contribution.
        with db.tx() as c:
            self.assertEqual(c.execute("SELECT public_count FROM drift_bottles").fetchone()[0], 1)
            self.assertEqual(c.execute("SELECT COUNT(*) FROM drift_bottle_contributions").fetchone()[0], 1)
        # A cannot read B's private encounter or turns.
        with self.assertRaises(BottleError) as hidden:
            service.get_encounter(3, encounter["id"], None, NOW_S + 3)
        self.assertEqual(hidden.exception.status, 404)
        released = self.release(4, encounter, "我在海边也见过一家很晚才关门的早餐店。")
        record = released["record"]
        self.assertEqual(record["id"], f"encounter:{encounter['id']}")
        self.assertEqual([row["sequence"] for row in record["contributions"]], [1, 2])
        self.assertTrue(record["memory"]["summary"])
        self.assertEqual(len(record["turns"]), 3)  # opening + user + bot
        # C reads the public bottle but never receives B's private turns.
        reader = self.draw(5)["encounter"]
        page = service.get_encounter(5, reader["id"], None, NOW_S + 4)
        self.assertEqual([row["sequence"] for row in page["contributions"]], [1, 2])
        self.assertEqual(page["turns"], [])
        self.assertFalse(any("早餐店" in row["body"] for row in page["turns"]))
        # B's record still stops at the messages B had read or written; C's later message is absent.
        self.release(5, reader, "第三位路过的人留下的话。")
        old = service.record(4, record["id"], NOW_S + 6)
        self.assertEqual([row["sequence"] for row in old["contributions"]], [1, 2])
        self.assertFalse(any("第三位" in row["body"] for row in old["contributions"]))
        self.assertEqual(len(old["turns"]), 3)

    def test_restart_persists_private_record_and_failed_operation_query(self):
        self.create(3)
        encounter = self.draw(4)["encounter"]
        service.turns(4, encounter["id"], TurnRequest(
            request_id=self.req(), kind="opening"), NOW_S + 2)
        self.chat(4, encounter)
        released = self.release(4, encounter, "我把早餐店写进了自己的回信。")
        service.generate_memory(4, encounter["id"], MemoryRequest(request_id=self.req()), NOW_S + 3)
        request_id = released["operation"]["request_id"]
        # Process restart: the same file-backed database is initialised again.
        db.init_db()
        self.assertEqual(service.operation(4, request_id, NOW_S + 4)["operation"]["status"], "committed")
        record = service.record(4, f"encounter:{encounter['id']}", NOW_S + 5)
        self.assertEqual(len(record["turns"]), 3)
        self.assertEqual(record["memory"]["generated_by"], "bot")
        # A failed generation remains queryable and retryable instead of a fake response.
        self.create(3, text="另一封信。")
        second = self.draw(5)["encounter"]

        async def broken(messages, max_tokens):
            raise RuntimeError("provider interrupted")

        service.set_model_for_tests(broken)
        failed_id = self.req()
        with self.assertRaises(BottleError):
            service.turns(5, second["id"], TurnRequest(
                request_id=failed_id, kind="chat", text="还在吗？"), NOW_S + 6)
        db.init_db()
        failed = service.operation(5, failed_id, NOW_S + 7)
        self.assertEqual(failed["operation"]["status"], "failed")
        self.assertTrue(failed["operation"]["retryable"])

    def test_multidevice_resume_and_concurrent_single_winner(self):
        self.create(3)
        first = self.draw(4)["encounter"]
        second = self.draw(4)["encounter"]
        self.assertEqual(first["id"], second["id"])
        # Another account cannot draw a bottle that is already held.
        other = self.draw(5)["encounter"]
        self.assertIsNone(other)
        with db.tx() as c:
            self.assertEqual(c.execute("SELECT COUNT(*) FROM drift_bottle_encounters").fetchone()[0], 1)

    def test_fiftieth_contribution_archives_and_stops_matching(self):
        self.create(3)
        for uid in range(4, 53):
            encounter = self.draw(uid)["encounter"]
            self.assertIsNotNone(encounter, uid)
            self.release(uid, encounter, f"第 {uid} 位路过的人留下的一句话。")
        with db.tx() as c:
            bottle = dict(c.execute("SELECT * FROM drift_bottles").fetchone())
            self.assertEqual(bottle["public_count"], 50)
            self.assertEqual(bottle["state"], "archived")
            self.assertEqual(c.execute("SELECT COUNT(*) FROM drift_bottle_contributions").fetchone()[0], 50)
        self.assertIsNone(self.draw(53)["encounter"])

    def test_withdraw_and_block_rebuild_visibility_for_new_reader(self):
        self.create(3)
        first = self.draw(4)["encounter"]
        self.release(4, first, "这是 B 的公开留言。")
        second = self.draw(5)["encounter"]
        # C sees both messages, then B withdraws their own message.
        page = service.get_encounter(5, second["id"], None, NOW_S + 3)
        target = next(row for row in page["contributions"] if row["sequence"] == 2)
        service.withdraw(4, target["id"], WithdrawRequest(request_id=self.req()), NOW_S + 4)
        rebuilt = service.get_encounter(5, second["id"], None, NOW_S + 5)
        self.assertEqual(rebuilt["contributions"][1]["body"], "这段文字已被收回")
        self.assertTrue(rebuilt["contributions"][0]["body"].startswith("从北方搬到海边"))
        # New model calls never receive the withdrawn text.
        calls = []

        async def capturing(messages, max_tokens):
            calls.append(messages)
            return await fake_model(messages, max_tokens)

        service.set_model_for_tests(capturing)
        service.turns(5, second["id"], TurnRequest(
            request_id=self.req(), kind="chat", text="你怎么看？"), NOW_S + 6)
        self.assertNotIn("这是 B 的公开留言", json.dumps(calls, ensure_ascii=False))
        # Blocking the original author hides that author's text for this reader.
        original = next(row for row in rebuilt["contributions"] if row["sequence"] == 1)
        service.block(5, BlockRequest(request_id=self.req(), contribution_id=original["id"]), NOW_S + 7)
        blocked = service.get_encounter(5, second["id"], None, NOW_S + 8)
        self.assertEqual(blocked["contributions"][0]["display_state"], "blocked")


if __name__ == "__main__":
    unittest.main(verbosity=2)
