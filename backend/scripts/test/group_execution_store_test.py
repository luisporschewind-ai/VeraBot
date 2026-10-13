#!/usr/bin/env python3
"""Atomic execution storage invariants; no live model or production database."""
import concurrent.futures
import threading
import unittest
from uuid import uuid4

from group_execution_test_support import GroupExecutionFixture, db
from verabot.db import group_execution_store as store
from verabot.services import group_dispatch
from verabot.services.group_routing import parse_decision


class GroupExecutionStoreTests(unittest.TestCase):
    def setUp(self):
        self.fx = GroupExecutionFixture()

    def request(self, *, message="hello", task_id=None, version=None):
        return {
            "client_request_id": str(uuid4()), "message": message,
            "target_member_ids": [], "everyone": False, "reply_to_message_id": None,
            "attachment_ids": [], "expected_task_id": task_id, "expected_version": version,
            "clarification_id": None,
        }

    def test_request_idempotency_before_routing(self):
        request = self.request()
        first = group_dispatch.submit(self.fx.user_id, self.fx.group_id, request)
        again = group_dispatch.submit(self.fx.user_id, self.fx.group_id, request)
        self.assertEqual(first["id"], again["id"])
        with db.tx() as c:
            self.assertEqual(c.execute("SELECT COUNT(*) FROM chat_group_task_inputs").fetchone()[0], 1)
            self.assertEqual(c.execute("SELECT COUNT(*) FROM chat_group_steps WHERE kind='route'").fetchone()[0], 1)

    def test_two_devices_answer_same_clarification_once(self):
        task_id = self.fx.insert_task(state="awaiting_user", version=4)
        with db.tx() as c:
            c.execute("INSERT INTO chat_group_clarifications(task_id,group_id,user_id,owner_member_id,original_request,missing_information,status,created_at,updated_at) VALUES (?,?,?,?,?,?,'awaiting_user','now','now')",
                      (task_id, self.fx.group_id, self.fx.user_id, self.fx.member_ids[0], "help", "[\"scope\"]"))
        barrier = threading.Barrier(2)
        def submit():
            barrier.wait(timeout=3)
            return group_dispatch.submit(self.fx.user_id, self.fx.group_id,
                self.request(message="answer", task_id=task_id, version=4))
        def attempt():
            try:
                return submit()["id"]
            except store.GroupExecutionError as exc:
                return exc.code
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda _: attempt(), range(2)))
        self.assertEqual(sum(isinstance(item, int) for item in results), 1)
        self.assertEqual(results.count("task_version_changed"), 1)

    def test_stop_fences_late_result_and_keeps_usage_once(self):
        task_id = self.fx.insert_task()
        input_id = self.fx.insert_input(task_id)
        step_id = self.fx.insert_step(task_id, input_id)
        stopped = store.stop(self.fx.user_id, self.fx.group_id, task_id, expected_version=1)
        self.assertEqual(stopped["state"], "stopped")
        self.assertFalse(store.save_snapshot(step_id, "lease-1", 1, "late"))
        self.assertFalse(store.commit_step(step_id, "lease-1", 1, {"content": "late"}))
        self.assertTrue(store.record_call("call-1", self.fx.user_id, self.fx.group_id, task_id,
                                          step_id, "group_chat", {"total_tokens": 5}, False))
        self.assertFalse(store.record_call("call-1", self.fx.user_id, self.fx.group_id, task_id,
                                           step_id, "group_chat", {"total_tokens": 5}, False))

    def test_cross_account_task_is_not_found(self):
        task_id = self.fx.insert_task()
        with self.assertRaises(store.GroupExecutionError) as error:
            store.snapshot(self.fx.other_user_id, self.fx.group_id, task_id)
        self.assertEqual(error.exception.status, 404)

    def test_apply_route_creates_one_member_step_and_locks_clarifier_owner(self):
        task = group_dispatch.submit(self.fx.user_id, self.fx.group_id, self.request())
        route = store.claim_next("test", "2026-10-12T00:00:00+00:00")
        self.assertEqual(route["kind"], "route")
        self.assertTrue(store.apply_route(route["id"], route["lease_token"], route["version"], {
            "intent": "clarify", "speaker_member_ids": [self.fx.member_ids[1]], "goal": "", 
            "missing_information": ["用途"], "clarification_id": None, "usage": {"total_tokens": 3},
            "usage_unknown": False,
        }))
        with db.tx() as c:
            clarifier = c.execute("SELECT * FROM chat_group_clarifications WHERE task_id=?", (task["id"],)).fetchone()
            self.assertEqual(clarifier["owner_member_id"], self.fx.member_ids[1])
            self.assertEqual(c.execute("SELECT COUNT(*) FROM chat_group_steps WHERE task_id=? AND kind='member'", (task["id"],)).fetchone()[0], 1)
            self.assertEqual(c.execute("SELECT COUNT(*) FROM usage_log WHERE user_id=? AND kind='group_routing'", (self.fx.user_id,)).fetchone()[0], 1)

    def test_clarification_owner_survives_followup_input(self):
        task = group_dispatch.submit(self.fx.user_id, self.fx.group_id, self.request())
        route = store.claim_next("test", "2026-10-12T00:00:00+00:00")
        owner = self.fx.member_ids[1]
        store.apply_route(route["id"], route["lease_token"], route["version"], {
            "intent": "clarify", "speaker_member_ids": [owner], "goal": "目标", 
            "missing_information": ["用途"], "clarification_id": None, "usage": None,
            "usage_unknown": True,
        })
        with db.tx() as c:
            c.execute("UPDATE chat_group_tasks SET state='awaiting_user' WHERE id=?", (task["id"],))
            c.execute("UPDATE chat_group_clarifications SET status='awaiting_user' WHERE task_id=?", (task["id"],))
            c.execute("UPDATE chat_group_steps SET status='awaiting_user' WHERE task_id=? AND kind='member'", (task["id"],))
            clarification_id = c.execute("SELECT id FROM chat_group_clarifications WHERE task_id=?", (task["id"],)).fetchone()[0]
        request = self.request(message="好的", task_id=task["id"], version=1)
        request["clarification_id"] = clarification_id
        group_dispatch.submit(self.fx.user_id, self.fx.group_id, request)
        snapshot, clarification, _history, _fairness = store.routing_context(self.fx.user_id, self.fx.group_id, task["id"])
        self.assertEqual(clarification["owner_member_id"], owner)
        group = {"id": self.fx.group_id, "members": [
            {"id": mid, "bot_id": bid, "name": str(mid), "available": True}
            for mid, bid in zip(self.fx.member_ids, self.fx.bot_ids)]}
        decision = parse_decision('{"intent":"respond","speaker_member_ids":[%d],"goal":"resolved","missing_information":[]}' % self.fx.member_ids[0],
                                  group, request, clarification, {})
        self.assertEqual(decision["speaker_member_ids"], [owner])


if __name__ == "__main__":
    unittest.main()
