"""Task 2: flow rules, limits, pagination and authorization."""
import json
import unittest
from uuid import uuid4

from pydantic import ValidationError

from scheduled_task_test_support import DBTest, db, NOW
from verabot.core import ratelimit
from verabot.db import drift_bottle_store as store
from verabot.services.drift_bottle import service
from verabot.services.drift_bottle.contracts import (
    BlockRequest, BottleError, ContributionInput, CreateBottleRequest, DrawRequest,
    ReleaseRequest, TurnRequest, HOLD_SECONDS,
)

NOW_S = NOW.timestamp()


async def fake_chat(messages, max_tokens):
    return json.dumps({"text": "我注意到信里那家还没找到的早餐店，也有点想知道后来找到了吗。"},
                      ensure_ascii=False), {}


class DriftRulesTests(DBTest):
    def setUp(self):
        super().setUp()
        ratelimit.reset()
        service.set_model_for_tests(fake_chat)
        with db.tx() as c:
            for uid in range(3, 56):
                c.execute("INSERT INTO users(id,username,password_hash,created_at) VALUES (?,?,?,?)",
                          (uid, f"user{uid}", "test", NOW.isoformat()))
                c.execute("INSERT INTO bots(id,user_id,name,created_at,allowed_tools) VALUES (?,?,?,?,?)",
                          (uid, uid, f"bot{uid}", NOW.isoformat(), "[]"))

    def tearDown(self):
        service.set_model_for_tests(None)
        super().tearDown()

    def req(self):
        return str(uuid4())

    def create(self, uid=3, text="我从南方搬来，还在找一家合适的早餐店。"):
        return service.create_bottle(uid, CreateBottleRequest(
            request_id=self.req(), bot_id=uid, body=text, authorship="owner"), NOW_S)

    def draw(self, uid):
        return service.draw(uid, DrawRequest(request_id=self.req(), bot_id=uid), NOW_S)

    def release(self, uid, encounter, text="我也想去那家早餐店看看。", now=None):
        contribution = ContributionInput(body=text, authorship="owner") if text is not None else None
        return service.release(uid, encounter["id"], ReleaseRequest(
            request_id=self.req(), lease_token=encounter["lease_token"],
            expected_version=encounter["bottle_version"], contribution=contribution),
            NOW_S + 1 if now is None else now)

    def test_expiry_at_86400_releases_without_losing_record(self):
        self.create()
        encounter = self.draw(4)["encounter"]
        before = service.state(4, NOW_S + HOLD_SECONDS - 1)
        self.assertIsNotNone(before["current"])
        self.assertIsNone(before["current"]["ended_at"])
        self.assertTrue(before["current"]["can_publish"])
        after = service.state(4, NOW_S + HOLD_SECONDS)
        self.assertIsNone(after["current"])
        self.assertFalse(after["has_active_encounter"])
        # The private record and factual memory survive; the encounter is marked expired.
        record = service.record(4, f"encounter:{encounter['id']}", NOW_S + HOLD_SECONDS + 1)
        self.assertEqual(record["encounter"]["end_reason"], "expired")
        self.assertFalse(record["encounter"]["can_publish"])
        self.assertIsNotNone(record["memory"])
        # Public append is refused, private chat is still allowed.
        with self.assertRaises(BottleError) as error:
            self.release(4, encounter, now=NOW_S + HOLD_SECONDS + 2)
        self.assertEqual(error.exception.code, "encounter_expired")
        chat = service.turns(4, encounter["id"], TurnRequest(
            request_id=self.req(), kind="chat", text="信里的早餐店让我想起楼下的豆浆。"),
            NOW_S + HOLD_SECONDS + 3)
        self.assertEqual(chat["turn"]["role"], "bot")
        with self.assertRaises(BottleError) as opening:
            service.turns(4, encounter["id"], TurnRequest(request_id=self.req(), kind="opening"),
                          NOW_S + HOLD_SECONDS + 4)
        self.assertEqual(opening.exception.code, "opening_only_active")

    def test_fiftieth_contribution_archives_and_pool_is_truthful(self):
        self.create()
        for uid in range(4, 53):
            encounter = self.draw(uid)["encounter"]
            self.assertIsNotNone(encounter, uid)
            self.release(uid, encounter, text=f"第 {uid} 位路过的人留下一句话。")
        with db.tx() as c:
            bottle = dict(c.execute("SELECT * FROM drift_bottles").fetchone())
            self.assertEqual(bottle["public_count"], 50)
            self.assertEqual(bottle["state"], "archived")
            self.assertEqual(c.execute("SELECT COUNT(*) FROM drift_bottle_contributions").fetchone()[0], 50)
            self.assertEqual(c.execute("SELECT COUNT(DISTINCT sequence) FROM drift_bottle_contributions")
                             .fetchone()[0], 50)
        # A new account finds an honestly empty pool, not a fabricated letter.
        empty = self.draw(53)
        self.assertIsNone(empty["encounter"])
        self.assertEqual(empty["operation"]["status"], "committed")

    def test_empty_pool_is_not_fake_message(self):
        state = service.state(4, NOW_S)
        self.assertIsNone(state["current"])
        self.assertFalse(state["has_active_encounter"])
        draw = self.draw(4)
        self.assertIsNone(draw["encounter"])
        with db.tx() as c:
            self.assertEqual(c.execute("SELECT COUNT(*) FROM drift_bottles").fetchone()[0], 0)
            self.assertEqual(c.execute("SELECT COUNT(*) FROM drift_bottle_contributions").fetchone()[0], 0)

    def test_own_seen_and_blocked_bottles_are_excluded(self):
        self.create(3)
        self.assertIsNone(self.draw(3)["encounter"])  # own public bottle
        first = self.draw(4)["encounter"]
        self.assertIsNotNone(first)
        self.release(4, first, text=None)
        self.assertIsNone(self.draw(4)["encounter"])  # already read
        self.create(3, text="另一封完全不同的信。")
        with db.tx() as c:
            contribution = c.execute("SELECT id FROM drift_bottle_contributions WHERE body LIKE '另一封%'").fetchone()[0]
        service.block(4, BlockRequest(request_id=self.req(), contribution_id=contribution), NOW_S)
        self.assertIsNone(self.draw(4)["encounter"])  # contains a blocked author

    def test_authorization_does_not_leak_existence(self):
        self.create(3)
        encounter = self.draw(4)["encounter"]
        with self.assertRaises(BottleError) as hidden:
            service.get_encounter(5, encounter["id"], None, NOW_S)
        self.assertEqual(hidden.exception.status, 404)
        with self.assertRaises(BottleError) as bot:
            service.draw(4, DrawRequest(request_id=self.req(), bot_id=3), NOW_S)
        self.assertEqual(bot.exception.status, 404)
        with self.assertRaises(BottleError) as lease:
            service.release(4, encounter["id"], ReleaseRequest(
                request_id=self.req(), lease_token="0" * 16, expected_version=encounter["bottle_version"],
                contribution=None), NOW_S + 1)
        self.assertEqual(lease.exception.status, 409)

    def test_pagination_does_not_show_messages_after_the_encounter(self):
        self.create()
        reader = self.draw(4)["encounter"]
        self.release(4, reader, text="第一站留言。")
        later = self.draw(5)["encounter"]
        page = service.get_encounter(5, later["id"], None, NOW_S + 2)
        self.assertEqual([row["sequence"] for row in page["contributions"]], [1, 2])
        self.assertEqual(len(page["contributions"]), 2)
        self.release(5, later, text="第三站留言。")
        old = service.record(4, f"encounter:{reader['id']}", NOW_S + 4)
        # The owner's own public message is kept; a later traveller's message is not.
        self.assertEqual([row["sequence"] for row in old["contributions"]], [1, 2])
        self.assertTrue(any("第一站留言" in row["body"] for row in old["contributions"]))
        self.assertFalse(any("第三站留言" in row["body"] for row in old["contributions"]))

    def test_public_lengths_and_emoji_use_unicode_code_points(self):
        text = "🌊" * 1000
        body = CreateBottleRequest(request_id=self.req(), bot_id=3, body=text, authorship="owner")
        self.assertEqual(len(body.body), 1000)
        with self.assertRaises(ValidationError):
            CreateBottleRequest(request_id=self.req(), bot_id=3, body="🌊" * 1001, authorship="owner")
        with self.assertRaises(ValidationError):
            CreateBottleRequest(request_id=self.req(), bot_id=3, body="   ", authorship="owner")
        with self.assertRaises(ValidationError):
            ContributionInput(body="x" * 1001, authorship="owner")
        # A composed family emoji is 7 Unicode code points (Swift unicodeScalars agrees).
        composed = "👨‍👩‍👧‍👦"
        self.assertEqual(len(composed), 7)

    def test_replayed_request_does_not_double_count_quota(self):
        request_id = self.req()
        body = CreateBottleRequest(request_id=request_id, bot_id=3, body="限流重放测试", authorship="owner")
        service.create_bottle(3, body, NOW_S)
        service.create_bottle(3, body, NOW_S + 1)
        self.assertEqual(ratelimit.count("drift:publish:3", 60), 1)
        for index in range(4):
            service.create_bottle(3, CreateBottleRequest(request_id=self.req(), bot_id=3,
                                                         body=f"第 {index} 封", authorship="owner"), NOW_S)
        with self.assertRaises(BottleError) as limited:
            service.create_bottle(3, CreateBottleRequest(request_id=self.req(), bot_id=3,
                                                         body="第六封", authorship="owner"), NOW_S)
        self.assertEqual(limited.exception.status, 429)
        self.assertEqual(limited.exception.code, "rate_limited")
        self.assertTrue(limited.exception.retry_after)

    def test_new_bottle_does_not_consume_current_hold(self):
        self.create(3)
        encounter = self.draw(4)["encounter"]
        self.assertIsNotNone(encounter)
        created = service.create_bottle(4, CreateBottleRequest(
            request_id=self.req(), bot_id=4, body="手上拿着别人的瓶子时，也可以写自己的新瓶。", authorship="owner"), NOW_S)
        self.assertEqual(created["record"]["kind"], "release")
        state = service.state(4, NOW_S + 1)
        self.assertEqual(state["current"]["id"], encounter["id"])
        self.assertTrue(state["has_active_encounter"])
        records = service.records(4, None, None, 20, NOW_S + 2)["records"]
        self.assertEqual({row["kind"] for row in records}, {"encounter", "release"})
        with db.tx() as c:
            self.assertEqual(c.execute("SELECT COUNT(*) FROM drift_bottles").fetchone()[0], 2)

    def test_quiet_opening_generates_nothing(self):
        self.create()
        encounter = self.draw(4)["encounter"]
        result = service.turns(4, encounter["id"], TurnRequest(
            request_id=self.req(), kind="opening", quiet=True), NOW_S)
        self.assertIsNone(result["turn"])
        self.assertTrue(result["encounter"]["quiet"])
        self.assertTrue(service.get_encounter(4, encounter["id"], None, NOW_S)["quiet"])
        with db.tx() as c:
            self.assertEqual(c.execute("SELECT COUNT(*) FROM drift_bottle_turns").fetchone()[0], 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
