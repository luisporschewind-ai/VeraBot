import asyncio
import unittest
from unittest.mock import patch
from uuid import uuid4
from group_execution_test_support import GroupExecutionFixture,db
from verabot.db import group_execution_store as s,group_store
from verabot.services import group_worker
from verabot.agents import group_runtime

class RuntimeRepairTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self): self.fx=GroupExecutionFixture()
    def prepare(self):
        t=s.create_input(self.fx.user_id,self.fx.group_id,{'client_request_id':str(uuid4()),'message':'目标','target_member_ids':[self.fx.member_ids[0]]})
        p=s.claim_next('test','2026-10-13T00:00:00+00:00');s.apply_route(p['id'],p['lease_token'],p['version'],{'intent':'respond','speaker_member_ids':[self.fx.member_ids[0]],'goal':'目标','missing_information':[]})
        return t
    async def test_empty_retry_counts_both_provider_calls_and_usage(self):
        t=self.prepare();calls=[]
        async def fake(*args,**kwargs):
            calls.append(1)
            if len(calls)==2:yield 'delta','完成'
            yield 'usage',{'total_tokens':3 if len(calls)==1 else 5}
        with patch.object(group_runtime.llm,'stream_chat',fake): await group_worker.process_one('test')
        with db.tx() as c:
            self.assertEqual(c.execute('SELECT call_count FROM chat_group_task_inputs').fetchone()[0],2)
            self.assertEqual(c.execute("SELECT SUM(total_tokens) FROM usage_log WHERE user_id=? AND kind='group_chat'",(self.fx.user_id,)).fetchone()[0],8)
    async def test_sixth_call_cannot_make_empty_retry(self):
        self.prepare();calls=[]
        with db.tx() as c:c.execute('UPDATE chat_group_task_inputs SET call_count=5')
        async def fake(*args,**kwargs): calls.append(1);yield 'usage',{'total_tokens':1}
        with patch.object(group_runtime.llm,'stream_chat',fake):await group_worker.process_one('test')
        self.assertEqual(len(calls),1)
    async def test_exhausted_daily_budget_never_calls_provider(self):
        self.prepare();calls=[]
        async def fake(*args,**kwargs):calls.append(1);yield 'delta','不应调用'
        with patch.object(group_runtime.db,'token_budget',return_value=(100,100)),patch.object(group_runtime.llm,'stream_chat',fake):await group_worker.process_one('test')
        self.assertEqual(calls,[])
    async def test_explicit_text_stop_needs_no_remaining_budget(self):
        t=self.prepare()
        s.create_input(self.fx.user_id,self.fx.group_id,{'client_request_id':str(uuid4()),'message':'停止','target_member_ids':[self.fx.member_ids[0]],'expected_task_id':t['id'],'expected_version':1})
        with patch.object(group_runtime.db,'token_budget',return_value=(100,100)):
            await group_worker.process_one('test')
        self.assertEqual(s.execution_snapshot(self.fx.user_id,self.fx.group_id)['task']['state'],'stopped')
    async def test_stop_closes_stalled_stream_preserves_tail_and_known_usage(self):
        t=self.prepare();ready=asyncio.Event();closed=asyncio.Event()
        async def fake(*args,**kwargs):
            try:
                yield 'delta','x'*256
                yield 'delta','TAIL'
                yield 'usage',{'total_tokens':77}
                ready.set();await asyncio.Event().wait()
            finally:closed.set()
        with patch.object(group_runtime.llm,'stream_chat',fake):
            worker=asyncio.create_task(group_worker.process_one('test'))
            await asyncio.wait_for(ready.wait(),1)
            s.stop(self.fx.user_id,self.fx.group_id,t['id'],1);group_worker.request_cancel(t['id'])
            try:await asyncio.wait_for(asyncio.shield(worker),0.5)
            except TimeoutError:
                worker.cancel()
                try:await worker
                except asyncio.CancelledError:pass
                self.fail('stalled provider must close promptly on stop')
        self.assertTrue(closed.is_set())
        with db.tx() as c:
            row=c.execute("SELECT content,status FROM chat_group_messages WHERE role='bot'").fetchone()
            # 有可用正文时公开为 completed；步骤/任务仍可为 stopped。
            self.assertTrue(row['content'].endswith('TAIL'));self.assertEqual(row['status'],'completed')
            self.assertEqual(c.execute("SELECT status FROM chat_group_steps WHERE kind='member' ORDER BY id DESC LIMIT 1").fetchone()[0],'stopped')
            self.assertEqual(c.execute("SELECT SUM(total_tokens) FROM usage_log WHERE user_id=? AND kind='group_chat'",(self.fx.user_id,)).fetchone()[0],77)

if __name__=='__main__':unittest.main()
