#!/usr/bin/env python3
"""Classifier request construction and strict member-ID validation."""
import json
import unittest
from unittest.mock import patch

import group_execution_test_support
from verabot.services import group_routing


class GroupRoutingTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.group = {"id": 8, "name": "G", "members": [
            {"id": 3, "bot_id": 8, "name": "A", "detail": "研究", "available": True},
            {"id": 4, "bot_id": 9, "name": "B", "detail": "写作", "available": True},
        ]}
        self.request = {"client_request_id": "r", "message": "请改写这封邮件", "target_member_ids": [],
                        "everyone": False, "reply_to_message_id": None, "attachment_ids": [],
                        "expected_task_id": None, "expected_version": None, "clarification_id": None}

    async def test_classifier_uses_group_context_and_validated_ids(self):
        calls = []
        async def complete(messages, *, max_tokens):
            calls.append((messages, max_tokens))
            return json.dumps({"intent": "respond", "speaker_member_ids": [4], "goal": "改写邮件",
                               "missing_information": []}), {"total_tokens": 9}
        history = [{"role": "user", "content": f"m{i}"} for i in range(30)]
        with patch.object(group_routing.llm, "complete_json", complete):
            decision = await group_routing.resolve(1, self.group, self.request, None, history, None, {})
        self.assertEqual(decision["speaker_member_ids"], [4])
        self.assertEqual(decision["intent"], "respond")
        self.assertEqual(decision["usage"]["total_tokens"], 9)
        self.assertEqual(calls[0][1], 512)
        prompt = json.loads(calls[0][0][1]["content"])
        self.assertEqual(len(prompt["recent_group_history"]), 24)
        self.assertNotIn("default_responder_bot_id", prompt)

    async def test_invalid_classifier_result_uses_dynamic_clarifier(self):
        async def fail(*args, **kwargs):
            raise RuntimeError("offline")
        with patch.object(group_routing.llm, "complete_json", fail):
            decision = await group_routing.resolve(1, self.group, self.request, None, [], None, {})
        self.assertEqual(decision["intent"], "clarify")
        self.assertEqual(decision["speaker_member_ids"], [3])
        self.assertTrue(decision["usage_unknown"])

    def test_invalid_member_id_is_not_accepted_from_json(self):
        decision = group_routing.parse_decision(
            '{"intent":"respond","speaker_member_ids":[999],"goal":"x","missing_information":[]}',
            self.group, self.request, None, {})
        self.assertIn(decision["speaker_member_ids"][0], {3, 4})
        self.assertTrue(decision["usage_unknown"])


if __name__ == "__main__":
    unittest.main()
