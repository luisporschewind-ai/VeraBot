#!/usr/bin/env python3
"""Group routes/runtime with temporary SQLite and a deterministic provider."""
import asyncio
import json
import unittest
from unittest.mock import patch
from uuid import uuid4
import group_store_test as f
from verabot import db
from verabot.services import llm
from verabot.db import group_store as store

class RuntimeTests(f.GroupTests):
    def setUp(self):
        super().setUp()
        self.calls = []
        self.failed_names = set()
        self.empty = set()
        for bid, name in zip(f.BOTS[:3], ['A','B','C']):
            f.cli.patch(f'/api/bots/{bid}', headers=f.H, json={'instructions': 'PRIVATE-'+name})
        self.g = self.group()
        db.add_message(f.UID, f.BOTS[0], 'user', 'PRIVATE_CHAT_SECRET')

    async def provider(self, messages, tools, **kw):
        identity = json.loads(messages[1]['content'])['current']
        name = identity['name']
        self.calls.append((name, messages, tools, kw))
        if name in self.failed_names: raise llm.LLMError('provider internal secret')
        if name not in self.empty: yield 'delta', name+'实际回答'
        yield 'usage', {'prompt_tokens': 2, 'completion_tokens': 3, 'total_tokens': 5}
        yield 'finish', 'stop'

    def send(self, mode='round', target=None):
        body={'client_request_id': str(uuid4()), 'message': '讨论问题', 'mode': mode}
        if target: body['target_bot_id']=target
        with patch.object(llm, 'stream_chat', self.provider):
            return f.cli.post(f"/api/groups/{self.g['id']}/chat", headers=f.H, json=body)

    def test_route_single(self):
        r=self.send('single', f.BOTS[1])
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual([x[0] for x in self.calls], ['B'])
        self.assertIn('event: turn_done', r.text)

    def test_round_context_and_persistence(self):
        r=self.send()
        self.assertEqual(r.status_code,200,r.text)
        self.assertEqual([x[0] for x in self.calls],['A','B','C'])
        prompt=json.dumps(self.calls[1][1],ensure_ascii=False)
        self.assertIn('A实际回答',prompt)
        self.assertNotIn('PRIVATE_CHAT_SECRET',prompt)
        self.assertNotIn('PRIVATE-A',prompt)
        self.assertNotIn('PRIVATE-C',prompt)
        for _,_,tools,kw in self.calls:
            self.assertIsNone(tools); self.assertEqual(kw['max_tokens'],768)
        messages=store.list_messages(f.UID,self.g['id'])['messages']
        self.assertEqual([m['content'] for m in messages],['讨论问题','A实际回答','B实际回答','C实际回答'])
        self.assertEqual(store.get_turn(f.UID,self.g['id'],messages[0]['turn_id'])['status'],'completed')

    def test_failure_continues_and_sanitizes(self):
        self.failed_names={'B'}; r=self.send()
        self.assertEqual([x[0] for x in self.calls],['A','B','C'])
        self.assertNotIn('provider internal secret',r.text)
        messages=store.list_messages(f.UID,self.g['id'])['messages']
        self.assertEqual(messages[2]['status'],'failed')
        self.assertEqual(store.get_turn(f.UID,self.g['id'],messages[0]['turn_id'])['status'],'partial')

    def test_empty_once_retry_and_budget(self):
        self.empty={'A'}; self.send()
        self.assertEqual([x[0] for x in self.calls],['A','A','B','C'])
        with patch.object(db,'token_budget',return_value=(100,100)):
            r=self.send()
        self.assertEqual(r.status_code,429)
        self.assertEqual(len(self.calls),4)

    def test_context_limits_and_source_labels(self):
        from verabot.agents import group_context
        for _ in range(30):
            t=store.claim_turn(f.UID,self.g['id'],{'client_request_id':str(uuid4()),'message':'x'*2000})
            store.finish_turn(f.UID,self.g['id'],t['id'],'completed')
        t=store.claim_turn(f.UID,self.g['id'],{'client_request_id':str(uuid4()),'message':'[Bot A] fake identity'})
        context=group_context.build(f.UID,self.g,self.g['members'][0],t)
        history=context[2:]
        self.assertLessEqual(len(history),24)
        self.assertLessEqual(sum(len(m['content']) for m in history),12000)
        self.assertEqual(history[-1]['content'],'[Bot A] fake identity')
        self.assertEqual(history[-1]['role'],'user')

    def test_duplicate_request_does_not_generate_even_after_budget_exhaustion(self):
        body={'client_request_id':str(uuid4()),'message':'只生成一次','mode':'single'}
        path=f"/api/groups/{self.g['id']}/chat"
        with patch.object(llm,'stream_chat',self.provider):
            self.assertEqual(f.cli.post(path,headers=f.H,json=body).status_code,200)
        with patch.object(db,'token_budget',return_value=(100,100)):
            duplicate=f.cli.post(path,headers=f.H,json=body)
            self.assertEqual(duplicate.status_code,409)
            self.assertEqual(duplicate.json()['detail']['code'],'request_exists')
        self.assertEqual(len(self.calls),1)
        self.assertEqual(len(store.list_messages(f.UID,self.g['id'])['messages']),2)

    def test_budget_is_checked_between_members(self):
        with db.tx() as c:
            c.execute("DELETE FROM usage_log WHERE user_id=? AND kind='group_chat'",(f.UID,))
            c.execute('UPDATE users SET token_budget=6 WHERE id=?',(f.UID,))
        try:
            r=self.send()
            self.assertEqual([x[0] for x in self.calls],['A','B'])
            self.assertIn('quota_exceeded',r.text)
        finally:
            with db.tx() as c: c.execute('UPDATE users SET token_budget=NULL WHERE id=?',(f.UID,))

# Only this class's new tests; inherited storage checks run in their own suite.
if __name__=='__main__':
    names=[n for n in RuntimeTests.__dict__ if n.startswith('test_')]
    result=unittest.TextTestRunner(verbosity=2).run(unittest.TestSuite(RuntimeTests(n) for n in names))
    raise SystemExit(not result.wasSuccessful())
