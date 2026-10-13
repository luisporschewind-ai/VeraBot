#!/usr/bin/env python3
"""Durable worker lifecycle, event replay, and stop/lease fencing."""
import asyncio
import concurrent.futures
import threading
import unittest
from datetime import datetime, timezone
from unittest.mock import patch
from uuid import uuid4

from group_execution_test_support import GroupExecutionFixture, db
from verabot.db import group_execution_store as store
from verabot.services import group_dispatch, group_worker


class GroupWorkerTests(unittest.TestCase):
    def setUp(self):
        self.fx = GroupExecutionFixture()

    def request(self, message="hello", *, task_id=None, version=None):
        return {"client_request_id": str(uuid4()), "message": message, "target_member_ids": [],
                "everyone": False, "reply_to_message_id": None, "attachment_ids": [],
                "expected_task_id": task_id, "expected_version": version, "clarification_id": None}

    def test_expired_or_shutdown_running_step_is_interrupted_not_replayed(self):
        task_id = self.fx.insert_task(state="running")
        input_id = self.fx.insert_input(task_id)
        step_id = self.fx.insert_step(task_id, input_id)
        self.assertEqual(store.recover_interrupted("2026-10-12T00:00:00+00:00"), 1)
        self.assertEqual(store.recover_interrupted("2026-10-12T00:00:01+00:00"), 0)
        with db.tx() as c:
            self.assertEqual(c.execute("SELECT status FROM chat_group_steps WHERE id=?", (step_id,)).fetchone()[0], "interrupted")
        self.assertIsNone(store.claim_next("restart", "2026-10-12T00:00:02+00:00"))

    def test_queued_unstarted_step_is_safe_to_claim_after_restart(self):
        task_id = self.fx.insert_task(state="queued")
        input_id = self.fx.insert_input(task_id)
        with db.tx() as c:
            c.execute("INSERT INTO chat_group_steps(task_id,input_id,group_id,user_id,kind,action_key,version,status,created_at) VALUES (?,?,?,?,'route','queued-route',1,'queued','now')",
                      (task_id, input_id, self.fx.group_id, self.fx.user_id))
        self.assertEqual(store.recover_interrupted("2026-10-12T00:00:00+00:00"), 0)
        step = store.claim_next("restart", "2026-10-12T00:00:01+00:00")
        self.assertEqual(step["kind"], "route")

    def test_stop_before_handoff_commit_has_no_successor(self):
        task_id = self.fx.insert_task(state="running")
        input_id = self.fx.insert_input(task_id)
        step_id = self.fx.insert_step(task_id, input_id)
        store.stop(self.fx.user_id, self.fx.group_id, task_id, 1)
        self.assertFalse(store.commit_step(step_id, "lease-1", 1,
                                           {"status": "completed", "content": "late", "next_steps": [{"member_id": self.fx.member_ids[1]}]}))
        with db.tx() as c:
            self.assertEqual(c.execute("SELECT COUNT(*) FROM chat_group_steps WHERE task_id=? AND id!=?", (task_id, step_id)).fetchone()[0], 0)

    def test_two_workers_cannot_claim_same_group_step(self):
        task_id = self.fx.insert_task(state="queued")
        input_id = self.fx.insert_input(task_id)
        with db.tx() as c:
            for key in ("route-1", "route-2"):
                c.execute("INSERT INTO chat_group_steps(task_id,input_id,group_id,user_id,kind,action_key,version,status,created_at) VALUES (?,?,?,?,'route',?,1,'queued','now')",
                          (task_id, input_id, self.fx.group_id, self.fx.user_id, key))
        barrier = threading.Barrier(2)
        def claim(_):
            barrier.wait(timeout=3)
            return store.claim_next("worker", datetime.now(timezone.utc).isoformat())
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            claimed = list(pool.map(claim, range(2)))
        self.assertEqual(sum(item is not None for item in claimed), 1)

    def test_new_input_waits_for_old_model_cleanup(self):
        old_task = self.fx.insert_task(state="running")
        input_id = self.fx.insert_input(old_task)
        old_step = self.fx.insert_step(old_task, input_id)
        store.stop(self.fx.user_id, self.fx.group_id, old_task, 1)
        new_task = group_dispatch.submit(self.fx.user_id, self.fx.group_id, self.request(message="new task"))
        self.assertIsNone(store.claim_next("worker", datetime.now(timezone.utc).isoformat()))
        store.interrupt_step(old_step, "lease-1", stopped=True)
        step = store.claim_next("worker", datetime.now(timezone.utc).isoformat())
        self.assertEqual(step["task_id"], new_task["id"])

    def test_disconnect_observer_does_not_stop_worker_and_event_commit_is_durable(self):
        async def scenario():
            task = group_dispatch.submit(self.fx.user_id, self.fx.group_id, self.request())
            async def route(user_id, group, request, snapshot, history, clarification, fairness):
                return {"intent": "respond", "speaker_member_ids": [self.fx.member_ids[0]], "goal": "done",
                        "missing_information": [], "clarification_id": None, "usage": {"total_tokens": 2},
                        "usage_unknown": False}
            async def run(step, should_stop, **kwargs):
                return {"content": "finished", "status": "completed", "action": {"kind": "completed"},
                        "usage": {"total_tokens": 4}, "usage_unknown": False}
            with patch.object(group_worker.group_routing, "resolve", route), patch.object(group_worker.group_runtime, "run_step", run):
                self.assertTrue(await group_worker.process_one("worker"))
                cursor = store.events(self.fx.user_id, self.fx.group_id, 0)[-1]["id"]
                before = store.snapshot(self.fx.user_id, self.fx.group_id, task["id"])
                self.assertEqual(before["state"], "queued")
                # Reading/reconnecting to persisted events does not signal cancellation.
                self.assertTrue(await group_worker.process_one("worker"))
            final = store.snapshot(self.fx.user_id, self.fx.group_id, task["id"])
            self.assertEqual(final["state"], "completed")
            self.assertGreater(store.events(self.fx.user_id, self.fx.group_id, cursor)[0]["id"], cursor)
            with db.tx() as c:
                self.assertEqual(c.execute("SELECT COUNT(*) FROM usage_log WHERE user_id=? AND kind IN ('group_chat','group_routing')", (self.fx.user_id,)).fetchone()[0], 2)
                self.assertEqual(c.execute("SELECT status FROM chat_group_messages WHERE role='bot'").fetchone()[0], "completed")
        asyncio.run(scenario())


if __name__ == "__main__":
    unittest.main()
