import unittest
from verabot.services.group_routing import parse_route


class GroupRoutingTests(unittest.TestCase):
    def test_invalid_or_ambiguous_target_falls_back_to_default(self):
        group = {"default_bot_id": 8, "members": [
            {"bot_id": 8, "id": 3, "available": True},
            {"bot_id": 9, "id": 4, "available": True},
        ]}
        self.assertEqual(parse_route('{"mode":"single","target_bot_id":999}', group),
                         {"mode": "single", "target_bot_id": 8})
        self.assertEqual(parse_route('not json', group), {"mode": "single", "target_bot_id": 8})

    def test_valid_group_discussion_routes_to_all(self):
        group = {"default_bot_id": 8, "members": [
            {"bot_id": 8, "id": 3, "available": True},
            {"bot_id": 9, "id": 4, "available": True},
        ]}
        self.assertEqual(parse_route('{"mode":"round","target_bot_id":null}', group),
                         {"mode": "round", "target_bot_id": None})


if __name__ == "__main__":
    unittest.main()
