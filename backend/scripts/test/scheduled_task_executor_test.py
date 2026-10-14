import asyncio
import importlib
from unittest.mock import patch
from scheduled_task_test_support import DBTest, db, NOW
from verabot.services.scheduled_tasks.contracts import ExecutionResult
from verabot.services.scheduled_tasks import service, clock, policy
from verabot.db import scheduled_run_store as runs
from verabot.services import llm

class ExecutorTests(DBTest):
    def job(self):
        with patch.object(clock,'now',return_value=NOW):
            t=service.create(1,self.payload(),'key')
            service.run_now(1,t['id'],'manual')
            with db.tx(immediate=True) as c: return runs.claim_next(c,'test',NOW)
    def test_independent_execution_and_accounting(self):
        job=self.job()
        with db.tx() as c:
            c.execute("INSERT INTO messages(user_id,bot_id,role,content,created_at) VALUES(1,1,'user','secret old chat','x')")
        executor=importlib.import_module('verabot.services.scheduled_tasks.executor')
        async def model(messages,tools,**kwargs):
            self.assertNotIn('secret old chat',str(messages))
            self.assertEqual(kwargs['max_tokens'],2048)
            return {'content':'{"state":"succeeded","text":"任务完成"}','_finish_reason':'stop'},{'total_tokens':7}
        with patch.object(clock,'now',return_value=NOW),patch.object(llm,'complete',model):
            result=asyncio.run(executor.run_scheduled(job))
        self.assertEqual(result.state,'succeeded')
        self.assertEqual(result.usage['total_tokens'],7)
        with db.tx() as c:
            self.assertEqual(c.execute("SELECT COUNT(*) FROM messages WHERE role='user'").fetchone()[0],1)
            self.assertEqual(c.execute('SELECT SUM(total_tokens) FROM usage_log').fetchone()[0],7)
    def test_forced_write_is_denied(self):
        job=self.job()
        executor=importlib.import_module('verabot.services.scheduled_tasks.executor')
        async def model(messages,tools,**kwargs):
            return {'tool_calls':[{'id':'malicious','type':'function','function':{'name':'create_reminder','arguments':'{"title":"bad"}'}}]}, {'total_tokens':2}
        with patch.object(clock,'now',return_value=NOW),patch.object(llm,'complete',model):
            result=asyncio.run(executor.run_scheduled(job))
        self.assertEqual(result.state,'failed')
        self.assertEqual(result.error_code,'permission_revoked')
        with db.tx() as c: self.assertEqual(c.execute('SELECT COUNT(*) FROM reminders').fetchone()[0],0)
    def test_schema_hint_cannot_grant_mcp_background_access(self):
        bot=db.get_bot(1,1); bot['allowed_tools']=['mcp__evil']
        tool={'full_name':'mcp__evil','mcp_name':'delete_everything','risk':'read','status':'active','def_hash':'x','accepted_hash':'x'}
        with patch('verabot.services.scheduled_tasks.policy.mcp.connected_tool_rows',return_value=[(tool,{'catalog_id':'unknown'})]):
            self.assertEqual(policy.snapshot_tools(1,bot),{})
    def test_budget_and_revocation(self):
        job=self.job()
        executor=importlib.import_module('verabot.services.scheduled_tasks.executor')
        with db.tx() as c: c.execute('UPDATE users SET token_budget=0 WHERE id=1')
        async def never(*args,**kwargs): self.fail('model must not run with no budget')
        with patch.object(clock,'now',return_value=NOW),patch.object(llm,'complete',never):
            result=asyncio.run(executor.run_scheduled(job))
        self.assertEqual(result.error_code,'quota_exceeded')
        with db.tx() as c: c.execute('DELETE FROM bots WHERE id=1')
        with patch.object(clock,'now',return_value=NOW),patch.object(llm,'complete',never):
            self.assertEqual(asyncio.run(executor.run_scheduled(job)).error_code,'bot_deleted')
    def test_success_at_budget_boundary_keeps_result(self):
        job=self.job()
        executor=importlib.import_module('verabot.services.scheduled_tasks.executor')
        with db.tx() as c: c.execute('UPDATE users SET token_budget=7 WHERE id=1')
        async def model(messages,tools,**kwargs):
            return {'content':'{"state":"succeeded","text":"完成"}'},{'total_tokens':7}
        with patch.object(clock,'now',return_value=NOW),patch.object(llm,'complete',model):
            self.assertEqual(asyncio.run(executor.run_scheduled(job)).state,'succeeded')
    def test_tool_call_limit_and_invalid_result(self):
        job=self.job()
        executor=importlib.import_module('verabot.services.scheduled_tasks.executor')
        async def model(messages,tools,**kwargs):
            return {'tool_calls':[{'id':str(i),'type':'function','function':{'name':'list_reminders','arguments':'{}'}} for i in range(3)]},{'completion_tokens':1,'total_tokens':1}
        with patch.object(clock,'now',return_value=NOW),patch.object(llm,'complete',model):
            result=asyncio.run(executor.run_scheduled(job))
        self.assertEqual(result.error_code,'tool_limit')
        self.assertEqual(len(result.trace_summary),6)
    def test_revoked_tool_before_actual_dispatch(self):
        job=self.job()
        executor=importlib.import_module('verabot.services.scheduled_tasks.executor')
        async def model(messages,tools,**kwargs):
            with db.tx() as c: c.execute("UPDATE bots SET allowed_tools='[]' WHERE id=1")
            return {'tool_calls':[{'id':'1','type':'function','function':{'name':'list_reminders','arguments':'{}'}}]}, {'total_tokens':1}
        with patch.object(clock,'now',return_value=NOW),patch.object(llm,'complete',model):
            self.assertEqual(asyncio.run(executor.run_scheduled(job)).error_code,'permission_revoked')
    def test_output_budget_is_shared_across_model_rounds(self):
        job=self.job()
        executor=importlib.import_module('verabot.services.scheduled_tasks.executor')
        requests=[]
        async def model(messages,tools,**kwargs):
            requests.append(kwargs['max_tokens'])
            if len(requests)==1:
                return {'tool_calls':[{'id':'read','type':'function','function':{'name':'list_reminders','arguments':'{}'}}]}, {'completion_tokens':2000,'total_tokens':2001}
            return {'content':'{"state":"succeeded","text":"完成"}'}, {'completion_tokens':40,'total_tokens':41}
        with patch.object(clock,'now',return_value=NOW),patch.object(llm,'complete',model):
            result=asyncio.run(executor.run_scheduled(job))
        self.assertEqual(requests,[2048,48])
        self.assertEqual(result.state,'succeeded')
    def test_missing_provider_usage_is_unknown(self):
        job=self.job()
        executor=importlib.import_module('verabot.services.scheduled_tasks.executor')
        async def model(messages,tools,**kwargs):
            return {'content':'{"state":"succeeded","text":"完成"}'}, {}
        with patch.object(clock,'now',return_value=NOW),patch.object(llm,'complete',model):
            result=asyncio.run(executor.run_scheduled(job))
        self.assertEqual(result.state,'succeeded')
        self.assertTrue(result.usage_unknown)
        self.assertEqual(result.usage,{})
    def test_partial_usage_stays_unknown_and_records_reported_lower_bound(self):
        job=self.job()
        executor=importlib.import_module('verabot.services.scheduled_tasks.executor')
        async def model(messages,tools,**kwargs):
            return {'content':'{"state":"succeeded","text":"完成"}'}, {'prompt_tokens':3,'completion_tokens':4}
        with patch.object(clock,'now',return_value=NOW),patch.object(llm,'complete',model):
            result=asyncio.run(executor.run_scheduled(job))
        self.assertEqual(result.usage,{'prompt_tokens':3,'completion_tokens':4})
        self.assertTrue(result.usage_unknown)
        with db.tx(immediate=True) as c:
            runs.finish(c,job['id'],job['lease_token'],ExecutionResult(text='完成',usage=result.usage,usage_unknown=True),NOW)
        with db.tx() as c:
            self.assertEqual(c.execute('SELECT total_tokens FROM usage_log').fetchone()[0],7)
            self.assertEqual(runs.attempts(c,job['id'])[0]['usage_unknown'],1)

if __name__ == '__main__':
    import unittest
    unittest.main()
