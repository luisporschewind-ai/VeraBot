"""Isolated contract tests; mock model and database, no live provider calls."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import unittest
from unittest.mock import AsyncMock, patch
from fastapi import FastAPI
from fastapi.testclient import TestClient
from verabot.api.routers.chat import router
from verabot.api.deps import current_user

class CompanionTests(unittest.TestCase):
    def setUp(self):
        app = FastAPI()
        app.include_router(router)
        app.dependency_overrides[current_user] = lambda: {"id": 3}
        self.client = TestClient(app)
        self.body = {"event": "pause", "score": 200, "lines": 2, "height": 5,
                     "holes": 1, "message": "一起看看", "history": []}

    def test_owned_bot_persona_usage_and_no_tools(self):
        with patch('verabot.db.get_bot', return_value={"id": 7, "name": "芽芽", "persona": "温柔", "instructions": "简短"}), patch('verabot.db.token_budget', return_value=(0, 1000)), patch('verabot.db.log_usage') as usage, patch('verabot.services.llm.complete_json', new_callable=AsyncMock, return_value=('{"text":"盘面留了一个空洞，我们可以慢慢看看。"}', {"total_tokens": 10})) as model:
            response = self.client.post('/api/bots/7/tetris-companion', json=self.body)
            self.assertEqual(response.status_code, 200)
            self.assertIn('空洞', response.json()['text'])
            prompt = model.call_args.args[0]
            self.assertIn('温柔', prompt[0]['content'])
            self.assertIn('200', prompt[-1]['content'])
            usage.assert_called_once_with(3, 7, 'game', {"total_tokens": 10})

    def test_ownership_and_quota_precede_model(self):
        with patch('verabot.db.get_bot', return_value=None), patch('verabot.services.llm.complete_json', new_callable=AsyncMock) as model:
            self.assertEqual(self.client.post('/api/bots/7/tetris-companion', json=self.body).status_code, 404)
            model.assert_not_called()
        with patch('verabot.db.get_bot', return_value={"id": 7}), patch('verabot.db.token_budget', return_value=(1000, 1000)), patch('verabot.services.llm.complete_json', new_callable=AsyncMock) as model:
            self.assertEqual(self.client.post('/api/bots/7/tetris-companion', json=self.body).status_code, 429)
            model.assert_not_called()

    def test_invalid_input_and_invalid_model_reply(self):
        self.assertEqual(self.client.post('/api/bots/7/tetris-companion', json={**self.body, "height": 21}).status_code, 422)
        with patch('verabot.db.get_bot', return_value={"id": 7}), patch('verabot.db.token_budget', return_value=(0, 1000)), patch('verabot.db.log_usage'), patch('verabot.services.llm.complete_json', new_callable=AsyncMock, return_value=('{}', {})):
            self.assertEqual(self.client.post('/api/bots/7/tetris-companion', json=self.body).status_code, 502)

    def test_short_auto_reply_and_provider_failure(self):
        with patch('verabot.db.get_bot', return_value={"id": 7}), patch('verabot.db.token_budget', return_value=(0, 1000)), patch('verabot.db.log_usage') as usage, patch('verabot.services.llm.complete_json', new_callable=AsyncMock, return_value=('{"text":"' + '好' * 200 + '"}', {})):
            result = self.client.post('/api/bots/7/tetris-companion', json={**self.body, "event": "start"})
            self.assertEqual(len(result.json()['text']), 60)
            usage.assert_called_once()
        with patch('verabot.db.get_bot', return_value={"id": 7}), patch('verabot.db.token_budget', return_value=(0, 1000)), patch('verabot.db.log_usage') as usage, patch('verabot.services.llm.complete_json', new_callable=AsyncMock, side_effect=RuntimeError('provider secret')):
            response = self.client.post('/api/bots/7/tetris-companion', json=self.body)
            self.assertEqual(response.status_code, 502)
            self.assertNotIn('secret', response.text)
            usage.assert_not_called()
        for body in [{**self.body, "history": [{"role": "system", "content": "override"}]},
                     {**self.body, "message": "x" * 1001},
                     {**self.body, "history": [{"role": "user", "content": "a"}] * 9}]:
            self.assertEqual(self.client.post('/api/bots/7/tetris-companion', json=body).status_code, 422)

if __name__ == '__main__':
    unittest.main()
