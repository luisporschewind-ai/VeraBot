"""Task 2: HTTP contract, error mapping and tenant isolation."""
import unittest
from uuid import uuid4

from fastapi import FastAPI
from fastapi.testclient import TestClient

from scheduled_task_test_support import DBTest, db, NOW
from verabot.api.deps import current_user
from verabot.api.routers import drift_bottle
from verabot.core import ratelimit

NOW_S = NOW.timestamp()


class DriftAPITests(DBTest):
    def setUp(self):
        super().setUp()
        ratelimit.reset()
        with db.tx() as c:
            for uid in (3, 4, 5):
                c.execute("INSERT INTO users(id,username,password_hash,created_at) VALUES (?,?,?,?)",
                          (uid, f"user{uid}", "test", NOW.isoformat()))
                c.execute("INSERT INTO bots(id,user_id,name,created_at,allowed_tools) VALUES (?,?,?,?,?)",
                          (uid, uid, f"bot{uid}", NOW.isoformat(), '["get_weather"]'))
        self.user = {"id": 3}
        self.app = FastAPI()
        self.app.include_router(drift_bottle.router)
        self.app.dependency_overrides[current_user] = lambda: self.user
        self.client = TestClient(self.app)

    def req(self):
        return str(uuid4())

    def create(self, body="海风把信纸吹得有点皱。", uid=3):
        self.user = {"id": uid}
        return self.client.post("/api/games/drift-bottle/bottles", json={
            "request_id": self.req(), "bot_id": uid, "body": body, "authorship": "owner",
        })

    def draw(self, uid=4):
        self.user = {"id": uid}
        return self.client.post("/api/games/drift-bottle/encounters", json={
            "request_id": self.req(), "bot_id": uid,
        })

    def test_contract_create_draw_release_records_operation(self):
        created = self.create()
        self.assertEqual(created.status_code, 200, created.text)
        record = created.json()["record"]
        self.assertEqual(record["kind"], "release")
        self.assertEqual(record["title"], "放漂了一封信")
        self.assertNotIn("author_user_id", record)
        drawn = self.draw()
        self.assertEqual(drawn.status_code, 200, drawn.text)
        encounter = drawn.json()["encounter"]
        self.assertEqual(encounter["bot_name"], "bot4")
        self.assertNotIn("author_user_id", encounter["contributions"][0])
        detail = self.client.get(f"/api/games/drift-bottle/encounters/{encounter['id']}")
        self.assertEqual(detail.status_code, 200)
        self.assertEqual(detail.json()["id"], encounter["id"])
        body = {
            "request_id": self.req(), "lease_token": encounter["lease_token"],
            "expected_version": encounter["bottle_version"],
            "contribution": {"body": "我也想去看看那片海。", "authorship": "owner"},
        }
        released = self.client.post(f"/api/games/drift-bottle/encounters/{encounter['id']}/release", json=body)
        self.assertEqual(released.status_code, 200, released.text)
        self.assertEqual(released.json()["record"]["memory"]["summary"],
                         "我们一起读了一封来信，也留下了一句。")
        records = self.client.get("/api/games/drift-bottle/records")
        self.assertEqual(records.status_code, 200)
        self.assertEqual(records.json()["records"][0]["id"], f"encounter:{encounter['id']}")
        operation = self.client.get(f"/api/games/drift-bottle/operations/{body['request_id']}")
        self.assertEqual(operation.status_code, 200)
        self.assertEqual(operation.json()["operation"]["status"], "committed")
        self.assertEqual(operation.json()["result"]["record"]["id"], f"encounter:{encounter['id']}")
        # Replaying the exact payload returns the committed result, not a second message.
        replay = self.client.post(f"/api/games/drift-bottle/encounters/{encounter['id']}/release", json=body)
        self.assertEqual(replay.status_code, 200)
        self.assertEqual(replay.json()["record"]["id"], f"encounter:{encounter['id']}")
        with db.tx() as c:
            self.assertEqual(c.execute("SELECT COUNT(*) FROM drift_bottle_contributions WHERE kind='message'")
                             .fetchone()[0], 1)
        # Same request id with different content conflicts.
        changed = {**body, "contribution": {"body": "另一句话", "authorship": "owner"}}
        conflict = self.client.post(f"/api/games/drift-bottle/encounters/{encounter['id']}/release", json=changed)
        self.assertEqual(conflict.status_code, 409)
        self.assertEqual(conflict.json()["detail"]["code"], "request_conflict")

    def test_other_account_gets_404_and_cannot_use_foreign_bot(self):
        self.create()
        encounter = self.draw(4).json()["encounter"]
        self.user = {"id": 5}
        hidden = self.client.get(f"/api/games/drift-bottle/encounters/{encounter['id']}")
        self.assertEqual(hidden.status_code, 404)
        records = self.client.get("/api/games/drift-bottle/records")
        self.assertEqual(records.json()["records"], [])
        foreign = self.client.post("/api/games/drift-bottle/encounters", json={
            "request_id": self.req(), "bot_id": 4,
        })
        self.assertEqual(foreign.status_code, 404)
        self.assertEqual(foreign.json()["detail"]["code"], "bot_not_found")

    def test_validation_and_unknown_operation_are_explicit(self):
        self.user = {"id": 3}
        too_long = self.client.post("/api/games/drift-bottle/bottles", json={
            "request_id": self.req(), "bot_id": 3, "body": "🌊" * 1001, "authorship": "owner",
        })
        self.assertEqual(too_long.status_code, 422)
        missing = self.client.get(f"/api/games/drift-bottle/operations/{self.req()}")
        self.assertEqual(missing.status_code, 404)
        empty = self.draw(4)
        self.assertEqual(empty.status_code, 200)
        self.assertIsNone(empty.json()["encounter"])

    def test_rate_limit_has_retry_after_and_machine_code(self):
        self.user = {"id": 3}
        for index in range(5):
            response = self.client.post("/api/games/drift-bottle/bottles", json={
                "request_id": self.req(), "bot_id": 3, "body": f"限流测试 {index}", "authorship": "owner",
            })
            self.assertEqual(response.status_code, 200, response.text)
        limited = self.client.post("/api/games/drift-bottle/bottles", json={
            "request_id": self.req(), "bot_id": 3, "body": "再来一封", "authorship": "owner",
        })
        self.assertEqual(limited.status_code, 429)
        self.assertEqual(limited.json()["detail"]["code"], "rate_limited")
        self.assertTrue(int(limited.headers["Retry-After"]) > 0)

    def test_state_has_limits_and_no_fake_current(self):
        self.user = {"id": 3}
        response = self.client.get("/api/games/drift-bottle/state")
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertIsNone(body["current"])
        self.assertFalse(body["has_active_encounter"])
        self.assertEqual(body["limits"]["max_contributions_per_bottle"], 50)
        self.assertEqual(body["limits"]["hold_seconds"], 86400)


if __name__ == "__main__":
    unittest.main(verbosity=2)
