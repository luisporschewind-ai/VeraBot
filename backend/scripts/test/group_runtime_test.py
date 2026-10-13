#!/usr/bin/env python3
"""Compatibility boundary: protocol-v2 callers cannot fall back to the legacy turn runtime."""
import unittest
from unittest.mock import patch
import group_store_test as fixture
from verabot.services import llm


class GroupRuntimeCompatibilityTests(fixture.GroupTests):
    def setUp(self):
        super().setUp()
        self.group_record = self.group()

    def test_legacy_chat_and_retry_routes_do_not_invoke_model(self):
        path = f"/api/groups/{self.group_record['id']}"
        chat = {"client_request_id": "11111111-1111-4111-8111-111111111111", "message": "旧格式消息", "mode": "single"}
        with patch.object(llm, "stream_chat", side_effect=AssertionError("legacy provider must not run")):
            response = fixture.cli.post(path + "/chat", headers=fixture.H, json=chat)
            self.assertEqual(response.status_code, 426)
            self.assertEqual(response.json()["detail"]["code"], "group_upgrade_required")
        self.assertEqual(fixture.cli.get(path + "/messages", headers=fixture.H).status_code, 200)


if __name__ == "__main__":
    names = [name for name in GroupRuntimeCompatibilityTests.__dict__ if name.startswith("test_")]
    result = unittest.TextTestRunner(verbosity=2).run(unittest.TestSuite(GroupRuntimeCompatibilityTests(name) for name in names))
    raise SystemExit(not result.wasSuccessful())
