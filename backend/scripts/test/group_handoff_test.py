#!/usr/bin/env python3
"""Structured handoff planning rules, isolated from model providers."""
import unittest
import json
from unittest.mock import patch

from group_execution_test_support import GroupExecutionFixture
from verabot.agents import group_runtime
from verabot.services import group_actions


class GroupHandoffTests(unittest.TestCase):
    def setUp(self):
        self.fx = GroupExecutionFixture()
        self.group = {"id": self.fx.group_id, "members": [
            {"id": mid, "bot_id": bid, "available": True}
            for mid, bid in zip(self.fx.member_ids, self.fx.bot_ids)]}
        self.task = {"id": 1, "group_id": self.fx.group_id, "goal": "写一份方案", "owner_member_id": self.fx.member_ids[0]}
        self.step = {"id": 21, "member_id": self.fx.member_ids[0], "consult_return_step_id": None,
                     "input": {"attachment_ids": []}}

    def validate(self, action):
        return group_actions.validate(self.fx.user_id, self.group, self.task, self.step, action)

    def test_consult_returns_to_original_owner(self):
        action = self.validate({"kind": "consult", "target_member_id": self.fx.member_ids[1],
                                "goal": "核对事实", "result": "已有背景"})
        planned = group_actions.next_steps(self.task, self.step, action)
        self.assertEqual(planned[0]["member_id"], self.fx.member_ids[1])
        self.assertEqual(planned[0]["consult_return_step_id"], self.step["id"])
        returned = group_actions.next_steps(self.task,
            {"id": 22, "member_id": self.fx.member_ids[1], "consult_return_step_id": self.step["id"]},
            {"kind": "completed", "result": "核对结果"})
        self.assertEqual(returned[0]["member_id"], self.fx.member_ids[0])
        self.assertEqual(returned[0]["result"], "核对结果")

    def test_handoff_changes_owner_without_return(self):
        action = self.validate({"kind": "handoff", "target_member_id": self.fx.member_ids[1],
                                "goal": "完成文案", "result": "已完成研究"})
        planned = group_actions.next_steps(self.task, self.step, action)
        self.assertEqual(len(planned), 1)
        self.assertEqual(planned[0]["member_id"], self.fx.member_ids[1])
        self.assertIsNone(planned[0]["consult_return_step_id"])

    def test_plain_text_mention_does_not_schedule(self):
        action = self.validate(None)
        self.assertEqual(action["kind"], "completed")
        self.assertEqual(group_actions.next_steps(self.task, self.step, action), [])

    def test_invalid_target_and_ambiguous_actions_are_rejected(self):
        with self.assertRaises(ValueError):
            self.validate({"kind": "handoff", "target_member_id": 999})
        with self.assertRaises(ValueError):
            self.validate({"kind": "completed", "target_member_id": self.fx.member_ids[1]})

    def test_clarifier_asks_once_then_waits(self):
        action = self.validate({"kind": "await_user", "result": "你希望方案用于什么场景？",
                                "missing_information": ["使用场景"]})
        self.assertEqual(group_actions.next_steps(self.task, self.step, action), [])
        with self.assertRaises(ValueError):
            self.validate({"kind": "await_user", "result": "", "missing_information": []})

    def test_resolved_clarification_handoff_keeps_all_requirements(self):
        action = self.validate({"kind": "handoff", "target_member_id": self.fx.member_ids[1],
                                "goal": "写完整方案", "result": "用户希望面向新手，预算固定"})
        planned = group_actions.next_steps(self.task, self.step, action)
        self.assertEqual(planned[0]["goal"], "写完整方案")
        self.assertIn("预算固定", planned[0]["result"])

    def test_six_calls_and_one_return_per_issue_are_bounded(self):
        self.assertTrue(group_actions.within_call_limit(5))
        self.assertFalse(group_actions.within_call_limit(6))
        self.assertTrue(group_actions.may_return_for_issue(0))
        self.assertFalse(group_actions.may_return_for_issue(1))


class GroupStepRuntimeTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.fx = GroupExecutionFixture()
        self.group = {"id": self.fx.group_id, "members": [
            {"id": mid, "bot_id": bid, "available": True}
            for mid, bid in zip(self.fx.member_ids, self.fx.bot_ids)]}
        self.task = {"id": 5, "group_id": self.fx.group_id, "goal": "目标", "owner_member_id": self.fx.member_ids[0]}
        self.step = {"id": 3, "member_id": self.fx.member_ids[0], "context": [{"role": "user", "content": "请继续"}],
                     "input": {"attachment_ids": []}, "consult_return_step_id": None}

    async def test_body_mention_does_not_schedule_and_internal_tool_is_available(self):
        seen = {}
        async def fake(messages, tools, *, tool_choice, max_tokens):
            seen.update(tool=tools[0]["function"]["name"], max_tokens=max_tokens)
            yield "delta", "我会把结果交给 B。"
            yield "finish", "stop"
        with patch.object(group_runtime.llm, "stream_chat", fake):
            result = await group_runtime.run_step(self.step, lambda: False, user_id=self.fx.user_id,
                group=self.group, task=self.task, member=self.group["members"][0])
        self.assertEqual(result["action"]["kind"], "completed")
        self.assertEqual(seen, {"tool": "group_next_step", "max_tokens": 768})

    async def test_one_structured_handoff_action_is_validated(self):
        calls = []
        async def fake(messages, tools, *, tool_choice, max_tokens):
            calls.append(1)
            action = {"kind": "handoff", "target_member_id": self.fx.member_ids[1], "goal": "写结果"}
            yield "tool_calls", [{"name": "group_next_step", "arguments": json.dumps(action)}]
            yield "usage", {"total_tokens": 5}
        with patch.object(group_runtime.llm, "stream_chat", fake):
            result = await group_runtime.run_step(self.step, lambda: False, user_id=self.fx.user_id,
                group=self.group, task=self.task, member=self.group["members"][0])
        self.assertEqual(result["action"]["target_member_id"], self.fx.member_ids[1])
        self.assertEqual(len(calls), 1)

    async def test_multiple_actions_are_rejected(self):
        async def fake(messages, tools, *, tool_choice, max_tokens):
            yield "tool_calls", [{"name": "group_next_step", "arguments": '{"kind":"completed"}'},
                                  {"name": "group_next_step", "arguments": '{"kind":"handoff"}'}]
        with patch.object(group_runtime.llm, "stream_chat", fake):
            result = await group_runtime.run_step(self.step, lambda: False, user_id=self.fx.user_id,
                group=self.group, task=self.task, member=self.group["members"][0])
        self.assertEqual(result["status"], "failed")
        self.assertIsNone(result["action"])


if __name__ == "__main__":
    unittest.main()
