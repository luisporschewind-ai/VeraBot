#!/usr/bin/env python3
"""Dynamic clarification selection and ownership rules."""
import json
import unittest

import group_execution_test_support  # adds backend to sys.path for direct script execution
from verabot.db.group_execution_types import GroupInput
from verabot.services.group_routing import choose_clarifier, parse_decision


class GroupClarificationTests(unittest.TestCase):
    def setUp(self):
        self.group = {"id": 1, "name": "G", "members": [
            {"id": 10, "bot_id": 1, "name": "A", "detail": "擅长研究", "available": True},
            {"id": 20, "bot_id": 2, "name": "B", "detail": "擅长写作", "available": True},
        ]}
        self.request: GroupInput = {"client_request_id": "r", "message": "", "target_member_ids": [],
            "everyone": False, "reply_to_message_id": None, "attachment_ids": [],
            "expected_task_id": None, "expected_version": None, "clarification_id": None}

    def test_clear_request_with_two_capable_bots_does_not_clarify(self):
        decision = parse_decision(json.dumps({"intent": "respond", "speaker_member_ids": [20],
            "goal": "改写邮件", "missing_information": []}), self.group, self.request, None, {})
        self.assertEqual(decision["intent"], "respond")
        self.assertEqual(decision["speaker_member_ids"], [20])

    def test_ambiguous_goal_selects_dynamic_clarifier(self):
        decision = parse_decision(json.dumps({"intent": "clarify", "speaker_member_ids": [],
            "goal": "", "missing_information": ["用户希望做什么"]}), self.group, self.request, None, {})
        self.assertEqual(decision["intent"], "clarify")
        self.assertEqual(decision["speaker_member_ids"], [10])

    def test_ok_preserves_owner_but_new_topic_releases_it(self):
        clarification = {"id": 4, "owner_member_id": 20, "original_request": "制定方案"}
        self.request["message"] = "好的"
        decision = parse_decision('{"intent":"continue","speaker_member_ids":[10],"goal":"方案","missing_information":[]}',
                                  self.group, self.request, clarification, {})
        self.assertEqual(decision["speaker_member_ids"], [20])
        self.request["message"] = "换个话题，帮我改这封邮件"
        changed = parse_decision('{"intent":"replace","speaker_member_ids":[10],"goal":"改邮件","missing_information":[]}',
                                 self.group, self.request, clarification, {})
        self.assertEqual(changed["intent"], "replace")
        self.assertEqual(changed["speaker_member_ids"], [10])

    def test_owner_unavailable_transfers_to_contextually_relevant_member(self):
        self.group["members"][1]["available"] = False
        self.request["message"] = "补充一下"
        decision = parse_decision('{"intent":"continue","speaker_member_ids":[20],"goal":"继续","missing_information":[]}',
            self.group, self.request, {"id": 4, "owner_member_id": 20, "original_request": "研究资料"}, {})
        self.assertEqual(decision["speaker_member_ids"], [10])

    def test_equal_fit_uses_fairness_and_stable_member_order(self):
        fairness = {10: {"last_clarified_at": "2026-10-10", "recent_speech_count": 1},
                    20: {"last_clarified_at": None, "recent_speech_count": 8}}
        self.assertEqual(choose_clarifier(self.group, [10, 20], None, fairness), 20)

    def test_same_name_does_not_forge_identity(self):
        self.group["members"][1]["name"] = self.group["members"][0]["name"] = "小智"
        self.request["message"] = "小智，帮我看看这个"
        decision = parse_decision('{"intent":"respond","speaker_member_ids":[10],"goal":"看看","missing_information":[]}',
                                  self.group, self.request, None, {})
        self.assertEqual(decision["intent"], "clarify")
        self.assertEqual(decision["missing_information"], ["用户指的是哪位同名成员"])

    def test_explicit_member_ids_are_identity_not_name_text(self):
        self.request["target_member_ids"] = [20]
        decision = parse_decision("not json", self.group, self.request, None, {})
        self.assertEqual(decision["speaker_member_ids"], [20])

    def test_router_failure_never_uses_legacy_default(self):
        decision = parse_decision("not json", self.group, self.request, None, {})
        self.assertIn(decision["speaker_member_ids"][0], {10, 20})
        self.assertTrue(decision["usage_unknown"])
        self.assertNotIn("default_bot_id", decision)


if __name__ == "__main__":
    unittest.main()
