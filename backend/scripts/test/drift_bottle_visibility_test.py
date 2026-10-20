"""Task 3: visibility, withdrawal, reports, blocks, admin and deletion."""
import json
import unittest
from uuid import uuid4

from scheduled_task_test_support import DBTest, db, NOW
from verabot.core import ratelimit
from verabot.db import drift_bottle_store as store
from verabot.services.drift_bottle import moderation, service
from verabot.services.drift_bottle.contracts import (
    BlockRequest, BottleError, ContributionInput, CreateBottleRequest, DrawRequest,
    ReleaseRequest, ReportRequest, TurnRequest, WithdrawRequest,
)

NOW_S = NOW.timestamp()


class DriftVisibilityTests(DBTest):
    def setUp(self):
        super().setUp()
        ratelimit.reset()
        with db.tx() as c:
            for uid in range(3, 56):
                c.execute("INSERT INTO users(id,username,password_hash,created_at) VALUES (?,?,?,?)",
                          (uid, f"user{uid}", "test", NOW.isoformat()))
                c.execute("INSERT INTO bots(id,user_id,name,created_at,allowed_tools) VALUES (?,?,?,?,?)",
                          (uid, uid, f"bot{uid}", NOW.isoformat(), "[]"))
        self.seen = []

        async def fake(messages, max_tokens):
            self.seen.append(messages)
            return json.dumps({"text": "我听见了信里那个具体的细节。"}, ensure_ascii=False), {}

        service.set_model_for_tests(fake)

    def tearDown(self):
        service.set_model_for_tests(None)
        super().tearDown()

    def req(self):
        return str(uuid4())

    def create(self, uid=3, text="信里藏着一个只属于作者的小秘密：蓝鲸早餐店。"):
        return service.create_bottle(uid, CreateBottleRequest(
            request_id=self.req(), bot_id=uid, body=text, authorship="owner"), NOW_S)

    def draw(self, uid):
        return service.draw(uid, DrawRequest(request_id=self.req(), bot_id=uid), NOW_S)

    def release(self, uid, encounter, text="路人留下的一句话。"):
        return service.release(uid, encounter["id"], ReleaseRequest(
            request_id=self.req(), lease_token=encounter["lease_token"],
            expected_version=encounter["bottle_version"],
            contribution=ContributionInput(body=text, authorship="owner") if text else None),
            NOW_S + 1)

    def contribution_ids(self):
        with db.tx() as c:
            return [row[0] for row in c.execute("SELECT id FROM drift_bottle_contributions ORDER BY sequence")]

    def chat(self, uid, encounter):
        return service.turns(uid, encounter["id"], TurnRequest(
            request_id=self.req(), kind="chat", text="我想知道那家店后来找到了吗？"), NOW_S + 2)

    def test_withdraw_keeps_placeholder_order_and_excludes_text_from_model(self):
        self.create()
        encounter = self.draw(4)["encounter"]
        self.release(4, encounter)
        reader = self.draw(5)["encounter"]
        origin_id = self.contribution_ids()[0]
        service.withdraw(3, origin_id, WithdrawRequest(request_id=self.req()), NOW_S + 3)
        page = service.get_encounter(5, reader["id"], None, NOW_S + 4)
        self.assertEqual(page["contributions"][0]["display_state"], "withdrawn")
        self.assertEqual(page["contributions"][0]["body"], "这段文字已被收回")
        self.assertEqual(page["contributions"][1]["body"], "路人留下的一句话。")
        self.chat(5, reader)
        self.assertNotIn("蓝鲸早餐店", json.dumps(self.seen, ensure_ascii=False))
        with db.tx() as c:
            bottle = dict(c.execute("SELECT * FROM drift_bottles").fetchone())
            self.assertEqual(bottle["public_count"], 2)  # withdrawal does not free a slot

    def test_report_hides_for_reporter_then_admin_hides_globally(self):
        self.create()
        first = self.draw(4)["encounter"]
        self.release(4, first)
        reader = self.draw(5)["encounter"]
        reported_id = self.contribution_ids()[1]
        response = service.report(5, ReportRequest(request_id=self.req(), contribution_id=reported_id,
                                                    reason="这段内容让我不舒服"), NOW_S + 3)
        report_id = response["report"]["id"]
        mine = service.get_encounter(5, reader["id"], None, NOW_S + 4)
        self.assertEqual(mine["contributions"][1]["display_state"], "reported")
        self.assertEqual(mine["contributions"][1]["body"], "你已举报这段内容")
        self.release(5, reader, text=None)
        second = self.draw(6)["encounter"]
        other = service.get_encounter(6, second["id"], None, NOW_S + 4)
        self.assertEqual(other["contributions"][1]["body"], "路人留下的一句话。")
        with db.tx(immediate=True) as c:
            moderation.moderate(c, 99, report_id, "hide", "管理员确认隐藏", NOW_S + 5, admins={99})
        hidden = service.get_encounter(6, second["id"], None, NOW_S + 6)
        self.assertEqual(hidden["contributions"][1]["display_state"], "hidden")
        self.assertEqual(hidden["contributions"][1]["body"], "这段内容已被隐藏")
        with db.tx(immediate=True) as c:
            moderation.moderate(c, 99, report_id, "restore", "误报，恢复", NOW_S + 7, admins={99})
        restored = service.get_encounter(6, second["id"], None, NOW_S + 8)
        self.assertEqual(restored["contributions"][1]["body"], "路人留下的一句话。")
        # An unconfigured account can never act as administrator.
        with db.tx(immediate=True) as c:
            with self.assertRaises(BottleError) as denied:
                moderation.moderate(c, 4, report_id, "hide", "", NOW_S + 9, admins={99})
        self.assertEqual(denied.exception.status, 403)

    def test_block_hides_existing_text_and_excludes_author(self):
        self.create(3)
        encounter = self.draw(5)["encounter"]
        contribution = self.contribution_ids()[0]
        service.block(5, BlockRequest(request_id=self.req(), contribution_id=contribution), NOW_S + 2)
        page = service.get_encounter(5, encounter["id"], None, NOW_S + 3)
        self.assertEqual(page["contributions"][0]["display_state"], "blocked")
        self.assertEqual(page["contributions"][0]["body"], "你已屏蔽这位投稿者")
        self.release(5, encounter, text=None)
        self.create(3, text="同一作者的另一封信。")
        self.assertIsNone(self.draw(5)["encounter"])
        # Another account is not affected by user 5's block and can still meet the author.
        self.assertIsNotNone(self.draw(6)["encounter"])
        with db.tx() as c:
            self.assertEqual(c.execute("SELECT COUNT(*) FROM drift_bottle_blocks").fetchone()[0], 1)

    def test_delete_record_keeps_public_text_and_read_marker(self):
        self.create()
        encounter = self.draw(4)["encounter"]
        self.release(4, encounter, text="我留下的一句话。")
        service.delete_record(4, f"encounter:{encounter['id']}", self.req(), NOW_S + 3)
        with self.assertRaises(BottleError) as gone:
            service.record(4, f"encounter:{encounter['id']}", NOW_S + 4)
        self.assertEqual(gone.exception.status, 404)
        with db.tx() as c:
            self.assertEqual(c.execute("SELECT public_count FROM drift_bottles").fetchone()[0], 2)
            self.assertEqual(c.execute("SELECT COUNT(*) FROM drift_bottle_turns").fetchone()[0], 0)
            self.assertEqual(c.execute("SELECT COUNT(*) FROM drift_bottle_memories").fetchone()[0], 0)
            self.assertTrue(c.execute("SELECT 1 FROM drift_bottle_reads WHERE user_id=4").fetchone())
        # The public text remains readable by a new traveller.
        later = self.draw(5)["encounter"]
        self.assertEqual(len(service.get_encounter(5, later["id"], None, NOW_S + 5)["contributions"]), 2)
        # The read marker still excludes the bottle from the same account.
        self.assertIsNone(self.draw(4)["encounter"])

    def test_delete_memory_only_keeps_record_and_public_text(self):
        self.create()
        encounter = self.draw(4)["encounter"]
        self.release(4, encounter, text=None)
        service.delete_memory(4, f"encounter:{encounter['id']}", self.req(), NOW_S + 3)
        record = service.record(4, f"encounter:{encounter['id']}", NOW_S + 4)
        self.assertIsNone(record["memory"])
        self.assertEqual(len(record["contributions"]), 1)
        with db.tx() as c:
            self.assertEqual(c.execute("SELECT public_count FROM drift_bottles").fetchone()[0], 1)

    def test_account_delete_withdraws_public_text_and_cleans_private_rows(self):
        self.create(3)
        encounter = self.draw(4)["encounter"]
        self.chat(4, encounter)
        self.release(4, encounter, text="我也留下一点回音。")
        with db.tx() as c:
            c.execute("DELETE FROM users WHERE id=3")
        with db.tx() as c:
            origin = dict(c.execute("SELECT * FROM drift_bottle_contributions WHERE sequence=1").fetchone())
            bottle = dict(c.execute("SELECT * FROM drift_bottles").fetchone())
            self.assertEqual(origin["state"], "withdrawn")
            self.assertEqual(origin["body"], "")
            self.assertIsNone(origin["author_user_id"])
            # The bottle keeps drifting because another person's visible message remains.
            self.assertEqual(bottle["state"], "active")
            self.assertEqual(bottle["public_count"], 2)
            self.assertIsNone(bottle["origin_user_id"])
        # Deleting the reader removes private turns but leaves their public contribution withdrawn.
        with db.tx() as c:
            c.execute("DELETE FROM users WHERE id=4")
        with db.tx() as c:
            message = dict(c.execute("SELECT * FROM drift_bottle_contributions WHERE sequence=2").fetchone())
            self.assertEqual(message["state"], "withdrawn")
            self.assertEqual(c.execute("SELECT COUNT(*) FROM drift_bottle_encounters").fetchone()[0], 0)
            self.assertEqual(c.execute("SELECT COUNT(*) FROM drift_bottle_turns").fetchone()[0], 0)
            self.assertEqual(c.execute("PRAGMA foreign_key_check").fetchall(), [])

    def test_deleted_bot_keeps_history_but_rejects_generation(self):
        self.create()
        encounter = self.draw(4)["encounter"]
        with db.tx() as c:
            c.execute("DELETE FROM bots WHERE id=4")
        record = service.record(4, f"encounter:{encounter['id']}", NOW_S + 2)
        self.assertTrue(record["encounter"]["bot_deleted"])
        self.assertEqual(record["encounter"]["bot_name"], "bot4")
        with self.assertRaises(BottleError) as error:
            service.turns(4, encounter["id"], TurnRequest(
                request_id=self.req(), kind="chat", text="还在吗？"), NOW_S + 3)
        self.assertEqual(error.exception.code, "bot_deleted")

    def test_full_archived_bottle_stays_archived_after_restore(self):
        self.create(3)
        with db.tx() as c:
            bottle = dict(c.execute("SELECT * FROM drift_bottles").fetchone())
            for sequence, uid in enumerate(range(4, 53), start=2):
                c.execute("""INSERT INTO drift_bottle_contributions
                    (bottle_id,author_user_id,sequence,kind,body,state,authorship,bot_id,bot_name,bot_avatar,bot_color,created_at)
                    VALUES(?,?,?,'message',?,'visible','owner',?,?,?,'#0F766E',?)""",
                          (bottle["id"], uid, sequence, f"第 {sequence} 条", uid, f"bot{uid}", "🤖", NOW_S))
            c.execute("UPDATE drift_bottles SET public_count=50,state='archived' WHERE id=?", (bottle["id"],))
            target = c.execute("SELECT id FROM drift_bottle_contributions WHERE sequence=2").fetchone()[0]
        response = service.report(53, ReportRequest(request_id=self.req(), contribution_id=target,
                                                    reason="测试举报"), NOW_S + 1)
        report_id = response["report"]["id"]
        with db.tx(immediate=True) as c:
            moderation.moderate(c, 99, report_id, "hide", "", NOW_S + 2, admins={99})
            moderation.moderate(c, 99, report_id, "restore", "", NOW_S + 3, admins={99})
        with db.tx() as c:
            self.assertEqual(c.execute("SELECT state FROM drift_bottles").fetchone()[0], "archived")
            self.assertEqual(c.execute("SELECT public_count FROM drift_bottles").fetchone()[0], 50)
        self.assertIsNone(self.draw(54)["encounter"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
