#!/usr/bin/env python3
"""HTTP contracts for group protocol v2 and durable input receipts."""
import unittest
from uuid import uuid4

import group_store_test as fixtures
from verabot import db
from verabot.services import group_dispatch

PROTOCOL = {"X-VeraBot-Group-Protocol": "2"}


class GroupExecutionAPITests(unittest.TestCase):
    def setUp(self):
        with db.tx(immediate=True) as c:
            c.execute("DELETE FROM chat_groups")
        response = fixtures.cli.post("/api/groups", headers={**fixtures.H, **PROTOCOL},
                                     json={"name": "Execution", "bot_ids": fixtures.BOTS[:2]})
        self.assertEqual(response.status_code, 201, response.text)
        self.group = response.json()
        self.path = f"/api/groups/{self.group['id']}"

    def request(self, message="请帮我看看", **kwargs):
        return {"client_request_id": str(uuid4()), "message": message, "target_member_ids": [],
                "everyone": False, "reply_to_message_id": None, "attachment_ids": [], **kwargs}

    def test_submit_ack_and_receipt_survive_observer_disconnect(self):
        request = self.request()
        response = fixtures.cli.post(self.path + "/inputs", headers={**fixtures.H, **PROTOCOL}, json=request)
        self.assertEqual(response.status_code, 202, response.text)
        receipt = fixtures.cli.get(self.path + "/inputs/" + request["client_request_id"], headers=fixtures.H)
        self.assertEqual(receipt.status_code, 200, receipt.text)
        self.assertEqual(receipt.json()["input_id"], response.json()["input_id"])

    def test_duplicate_submit_returns_same_input_without_second_route(self):
        request = self.request()
        first = fixtures.cli.post(self.path + "/inputs", headers={**fixtures.H, **PROTOCOL}, json=request)
        second = fixtures.cli.post(self.path + "/inputs", headers={**fixtures.H, **PROTOCOL}, json=request)
        self.assertEqual(first.status_code, 202)
        self.assertEqual(second.status_code, 200)
        self.assertEqual(first.json()["input_id"], second.json()["input_id"])
        with db.tx() as c:
            self.assertEqual(c.execute("SELECT COUNT(*) FROM chat_group_steps WHERE kind='route'").fetchone()[0], 1)

    def test_old_protocol_writes_are_426_and_history_is_readable(self):
        old = fixtures.cli.post(self.path + "/chat", headers=fixtures.H,
                                 json={"client_request_id": str(uuid4()), "message": "旧写入"})
        self.assertEqual(old.status_code, 426, old.text)
        history = fixtures.cli.get(self.path + "/messages", headers=fixtures.H)
        self.assertEqual(history.status_code, 200)

    def test_create_rename_and_meta_need_no_default_member(self):
        renamed = fixtures.cli.patch(self.path, headers={**fixtures.H, **PROTOCOL}, json={"name": "新名称"})
        self.assertEqual(renamed.status_code, 200, renamed.text)
        self.assertNotIn("default_bot_id", renamed.json())
        meta = fixtures.cli.get("/api/meta", headers=fixtures.H)
        self.assertEqual(meta.json()["group_protocol_version"], 2)

    def test_reply_reference_and_event_cursor_cannot_cross_group_or_account(self):
        body = self.request(reply_to_message_id=999999)
        response = fixtures.cli.post(self.path + "/inputs", headers={**fixtures.H, **PROTOCOL}, json=body)
        self.assertEqual(response.status_code, 404)
        events = fixtures.cli.get(self.path + "/events?after_id=0", headers=fixtures.H2)
        self.assertEqual(events.status_code, 404)

    def test_stop_waiting_clarification_without_running_turn(self):
        request = self.request()
        task = group_dispatch.submit(fixtures.UID, self.group["id"], request)
        with db.tx() as c:
            c.execute("UPDATE chat_group_tasks SET state='awaiting_user' WHERE id=?", (task["id"],))
            c.execute("INSERT INTO chat_group_clarifications(task_id,group_id,user_id,owner_member_id,original_request,missing_information,status,created_at,updated_at) VALUES (?,?,?,?,?,?,'awaiting_user','now','now')",
                      (task["id"], self.group["id"], fixtures.UID, self.group["members"][0]["id"], "help", '["用途"]'))
        response = fixtures.cli.post(self.path + f"/tasks/{task['id']}/stop", headers={**fixtures.H, **PROTOCOL},
                                     json={"client_request_id": str(uuid4()), "expected_version": 1})
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["state"], "stopped")

    def test_retry_only_failed_member_step(self):
        with db.tx() as c:
            task_id = c.execute("INSERT INTO chat_group_tasks(group_id,user_id,goal,state,version,created_at,updated_at) VALUES (?,?,?,'failed',1,'now','now')",
                                (self.group["id"], fixtures.UID, "目标")).lastrowid
            turn_id = c.execute("INSERT INTO chat_group_turns(group_id,user_id,client_request_id,request_hash,mode,status,created_at) VALUES (?,?,?,'hash','single','failed','now')",
                                (self.group["id"], fixtures.UID, str(uuid4()))).lastrowid
            user_message_id = c.execute("INSERT INTO chat_group_messages(group_id,user_id,turn_id,role,content,status,created_at,finished_at) VALUES (?,?,?,'user','问题','completed','now','now')",
                                        (self.group["id"], fixtures.UID, turn_id)).lastrowid
            c.execute("UPDATE chat_group_turns SET user_message_id=?,context_end_message_id=? WHERE id=?", (user_message_id, user_message_id, turn_id))
            input_id = c.execute("INSERT INTO chat_group_task_inputs(task_id,group_id,user_id,client_request_id,request_hash,message,turn_id,created_at) VALUES (?,?,?,?,?,'问题',?,'now')",
                                 (task_id, self.group["id"], fixtures.UID, str(uuid4()), "hash", turn_id)).lastrowid
            failed_message = c.execute("INSERT INTO chat_group_messages(group_id,user_id,turn_id,role,member_id,content,status,created_at,finished_at) VALUES (?,?,?,'bot',?,'部分内容','failed','now','now')",
                                       (self.group["id"], fixtures.UID, turn_id, self.group["members"][0]["id"])).lastrowid
            c.execute("INSERT INTO chat_group_steps(task_id,input_id,group_id,user_id,kind,action_key,version,member_id,status,result_json,created_at,finished_at) VALUES (?,?,?,?,'member','failed-step',1,?,'failed',?,'now','now')",
                      (task_id, input_id, self.group["id"], fixtures.UID, self.group["members"][0]["id"],
                       '{"message_id":%d}' % failed_message))
        response = fixtures.cli.post(self.path + f"/messages/{failed_message}/retry-v2",
            headers={**fixtures.H, **PROTOCOL}, json={"client_request_id": str(uuid4()), "expected_version": 1})
        self.assertEqual(response.status_code, 202, response.text)
        self.assertEqual(response.json()["version"], 2)
        with db.tx() as c:
            rows = c.execute("SELECT kind,status FROM chat_group_steps WHERE task_id=? ORDER BY id", (task_id,)).fetchall()
            self.assertEqual([(r["kind"], r["status"]) for r in rows], [("member", "failed"), ("member", "queued")])

    def test_clear_waiting_task_fences_late_worker_result(self):
        request = self.request()
        task = group_dispatch.submit(fixtures.UID, self.group["id"], request)
        from verabot.db import group_execution_store as store
        running = store.claim_next("test", "2026-10-12T00:00:00+00:00")
        response = fixtures.cli.delete(self.path + "/messages", headers={**fixtures.H, **PROTOCOL})
        self.assertEqual(response.status_code, 200, response.text)
        self.assertFalse(store.commit_step(running["id"], running["lease_token"], running["version"],
                                           {"status": "completed", "content": "late"}))
        self.assertEqual(fixtures.cli.get(self.path + "/messages", headers=fixtures.H).json()["messages"], [])
        self.assertEqual(store.snapshot(fixtures.UID, self.group["id"], task["id"])["state"], "stopped")


if __name__ == "__main__":
    unittest.main()
