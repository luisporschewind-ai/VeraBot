"""Multi-image acceptance uses temporary storage; no live model or user data."""
import io
import unittest
from uuid import uuid4

import group_store_test as fixtures
from PIL import Image
from verabot.services.attachments import repo, vision


class MultiAttachmentTests(unittest.TestCase):
    def upload(self, headers=None, bot_id=None):
        data = io.BytesIO()
        Image.new("RGB", (24, 16), "red").save(data, "JPEG")
        result = fixtures.cli.post("/api/attachments", headers=headers or fixtures.H,
                                  data={"bot_id": str(bot_id)} if bot_id else {},
                                  files={"file": ("image.jpg", data.getvalue(), "image/jpeg")})
        self.assertEqual(result.status_code, 201, result.text)
        return result.json()["id"]

    def test_private_nine_images_bound_to_one_message_and_all_reach_model(self):
        bid = fixtures.BOTS[0]
        ids = [self.upload(bot_id=bid) for _ in range(9)]
        result = fixtures.cli.post(f"/api/bots/{bid}/chat/inputs", headers=fixtures.H,
                                  json={"client_request_id": str(uuid4()), "expected_generation": 1,
                                        "message": "", "attachment_ids": ids})
        self.assertIn(result.status_code, (200, 202), result.text)
        rows = [repo.get(fixtures.UID, aid) for aid in ids]
        self.assertEqual(len({r["message_id"] for r in rows}), 1)
        self.assertTrue(all(r["status"] == "attached" for r in rows))
        parts = vision.user_content("", rows)
        self.assertEqual(sum(p["type"] == "image_url" for p in parts), 9)
        history = fixtures.cli.get(f"/api/bots/{bid}/messages", headers=fixtures.H).json()["messages"]
        self.assertEqual([a["id"] for a in next(m for m in history if m["id"] == rows[0]["message_id"])["attachments"]], ids)

    def test_group_nine_images_and_idempotent_resubmit(self):
        headers = {**fixtures.H, **fixtures.GH}
        group = fixtures.cli.post("/api/groups", headers=headers,
                                  json={"name": "Multi", "bot_ids": fixtures.BOTS[:2]}).json()
        ids = [self.upload() for _ in range(9)]
        body = {"client_request_id": str(uuid4()), "message": "", "attachment_ids": ids}
        url = f"/api/groups/{group['id']}/inputs"
        first = fixtures.cli.post(url, headers=headers, json=body)
        self.assertEqual(first.status_code, 202, first.text)
        again = fixtures.cli.post(url, headers=headers, json=body)
        self.assertEqual(again.status_code, 200, again.text)
        self.assertEqual(first.json()["input_id"], again.json()["input_id"])
        history = fixtures.cli.get(f"/api/groups/{group['id']}/messages", headers=fixtures.H).json()["messages"]
        self.assertEqual(len(history), 1)
        self.assertEqual([a["id"] for a in history[0]["attachments"]], ids)

    def test_ten_rejected_before_any_binding(self):
        ids = [self.upload() for _ in range(10)]
        with self.assertRaises(repo.AttachmentError):
            repo.check_pending(fixtures.UID, fixtures.BOTS[1], ids)
        for aid in ids:
            self.assertEqual(repo.get(fixtures.UID, aid)["status"], "pending")
        group = fixtures.cli.post("/api/groups", headers={**fixtures.H, **fixtures.GH},
                                  json={"name": "Limit", "bot_ids": fixtures.BOTS[:2]}).json()
        endpoints = [(f"/api/bots/{fixtures.BOTS[1]}/chat/inputs", {"expected_generation": 1}, fixtures.H),
                     (f"/api/groups/{group['id']}/inputs", {}, {**fixtures.H, **fixtures.GH})]
        for path, extra, headers in endpoints:
            result = fixtures.cli.post(path, headers=headers, json={"client_request_id": str(uuid4()),
                                      "message": "", "attachment_ids": ids, **extra})
            self.assertEqual(result.status_code, 422)

    def test_foreign_image_rejects_whole_batch_without_partial_binding(self):
        own = [self.upload() for _ in range(8)]
        foreign = self.upload(headers=fixtures.H2)
        ids = [*own, foreign]
        group = fixtures.cli.post("/api/groups", headers={**fixtures.H, **fixtures.GH},
                                  json={"name": "Isolation", "bot_ids": fixtures.BOTS[:2]}).json()
        endpoints = [(f"/api/bots/{fixtures.BOTS[2]}/chat/inputs", {"expected_generation": 1}, fixtures.H),
                     (f"/api/groups/{group['id']}/inputs", {}, {**fixtures.H, **fixtures.GH})]
        for path, extra, headers in endpoints:
            result = fixtures.cli.post(path, headers=headers, json={"client_request_id": str(uuid4()),
                                      "message": "", "attachment_ids": ids, **extra})
            self.assertEqual(result.status_code, 404, result.text)
            self.assertTrue(all(repo.get(fixtures.UID, aid)["status"] == "pending" for aid in own))



if __name__ == "__main__":
    unittest.main()
