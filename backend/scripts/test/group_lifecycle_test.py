#!/usr/bin/env python3
"""The old request-bound lifecycle is retired; task lifecycle lives on v2 endpoints."""
import unittest
from uuid import uuid4
import group_store_test as fixture


class GroupLifecycleCompatibilityTests(fixture.GroupTests):
    def setUp(self):
        super().setUp()
        self.group_record = self.group()

    def test_legacy_turn_stop_and_retry_cannot_bypass_task_versions(self):
        path = f"/api/groups/{self.group_record['id']}"
        stop = fixture.cli.post(path + "/turns/1/stop", headers=fixture.H, json={})
        retry = fixture.cli.post(path + "/messages/1/retry", headers=fixture.H,
                                 json={"client_request_id": str(uuid4())})
        self.assertEqual(stop.status_code, 426)
        self.assertEqual(retry.status_code, 426)
        self.assertEqual(stop.json()["detail"]["code"], "group_upgrade_required")
        self.assertEqual(retry.json()["detail"]["code"], "group_upgrade_required")


if __name__ == "__main__":
    names = [name for name in GroupLifecycleCompatibilityTests.__dict__ if name.startswith("test_")]
    result = unittest.TextTestRunner(verbosity=2).run(unittest.TestSuite(GroupLifecycleCompatibilityTests(name) for name in names))
    raise SystemExit(not result.wasSuccessful())
