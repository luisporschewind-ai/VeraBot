"""Focused review reproductions; isolated DB, fake providers, real permission/action paths."""
import asyncio
import json
import unittest
from unittest.mock import patch
import chat_continuity_test as fixture
from verabot import db
from verabot.db import chat_reply_store as store, action_store, mcp_store
from verabot.services.chat_tasks import worker
from verabot.services import actions
from verabot.tools.registry import REGISTRY, ToolContext, TurnState

class ReviewTests(unittest.TestCase):
    setUp=fixture.ContinuityTests.setUp
    tearDown=fixture.ContinuityTests.tearDown
    submit=fixture.ContinuityTests.submit

    def allow(self,names):
        with db.tx() as c:c.execute('UPDATE bots SET allowed_tools=? WHERE id=?',(json.dumps(names),self.bid))

    def claimed(self):
        self.submit()
        with db.tx(immediate=True) as c:return store.claim_next(c,'fixture')

    def mcp_fixture(self):
        name='mcp__fixture__write'
        server=mcp_store.insert_server(self.uid,dict(slug='fixture',catalog_id='fixture',name='Fixture',transport='http',url='http://127.0.0.1:1',trust='test',auth='none'),'connected')
        mcp_store.upsert_tool(self.uid,server['id'],dict(full_name=name,mcp_name='write',description='fixture',input_schema={'type':'object'},def_hash='hash',risk='write'))
        return name,server,mcp_store.get_tool_by_full_name(self.uid,name)

    def test_I1_revocation_during_provider_uses_current_dispatch_permissions(self):
        self.allow(['list_reminders']);self.submit();ran=[]
        async def handler(ctx,**kw):ran.append('called');return {'items':[]}
        async def model(messages,*a,**k):
            if any(m['role']=='tool' for m in messages):yield 'delta','done';return
            self.allow([])
            yield 'tool_calls',[{'id':'revoked','name':'list_reminders','arguments':'{}'}]
        with patch.object(REGISTRY['list_reminders'],'handler',handler),patch('verabot.services.llm.stream_chat',model):asyncio.run(worker.process_one('w'))
        self.assertEqual(ran,[])
        task=self.client.get(f'/api/bots/{self.bid}/chat/execution').json()['tasks'][0]
        self.assertEqual(task['traces'][0]['result']['code'],'tool_not_allowed')

    def test_I1_revocation_between_calls_and_checkpoint_pending_call(self):
        self.allow(['list_reminders','manage_reminder']);self.submit();ran=[]
        async def first(ctx,**kw):self.allow(['list_reminders']);return {'items':[]}
        async def second(ctx,**kw):ran.append('write');return {'ok':True}
        async def model(messages,*a,**k):
            if any(m['role']=='tool' for m in messages):yield 'delta','done';return
            yield 'tool_calls',[{'id':'one','name':'list_reminders','arguments':'{}'},{'id':'two','name':'manage_reminder','arguments':'{}'}]
        with patch.object(REGISTRY['list_reminders'],'handler',first),patch.object(REGISTRY['manage_reminder'],'handler',second),patch('verabot.services.llm.stream_chat',model):asyncio.run(worker.process_one('w'))
        self.assertEqual(ran,[])
        # A checkpoint's pending calls must recheck current grants, not a restored Bot snapshot.
        self.allow(['manage_reminder']);t=self.claimed_wait_pending('pending','manage_reminder')
        self.allow([])
        with patch.object(REGISTRY['manage_reminder'],'handler',second),patch('verabot.services.llm.stream_chat',model):asyncio.run(worker.process_one('w'))
        self.assertEqual(ran,[])

    def test_I1_new_grant_does_not_expand_accepted_authorization(self):
        self.allow([]);self.submit();self.allow(['list_reminders']);ran=[]
        async def handler(ctx,**kw):ran.append('newgrant');return {'items':[]}
        async def model(messages,*a,**k):
            if any(m['role']=='tool' for m in messages):yield 'delta','done';return
            yield 'tool_calls',[{'id':'newgrant','name':'list_reminders','arguments':'{}'}]
        with patch.object(REGISTRY['list_reminders'],'handler',handler),patch('verabot.services.llm.stream_chat',model):asyncio.run(worker.process_one('w'))
        self.assertEqual(ran,[])

    def claimed_wait_pending(self,key,name):
        self.submit(key)
        with db.tx(immediate=True) as c:
            t=store.claim_next(c,'w')
            call={'id':'pending','name':name,'arguments':'{}'}
            cp={'messages':[{'role':'user','content':'original'},{'role':'assistant','content':None,'tool_calls':[{'id':'pending','type':'function','function':{'name':name,'arguments':'{}'}}]}],'traces':[],'answer':'','round':1,'pending_calls':[call]}
            c.execute('UPDATE chat_reply_tasks SET checkpoint_json=? WHERE id=?',(store.encode_checkpoint(cp),t['id']))
            store.finish(c,t,'awaiting_user','question',[],wait_id='w')
            store.control(c,self.uid,self.bid,t['id'],{'client_request_id':'answer','expected_version':1,'wait_id':'w','message':'answer'},answer=True)
        return t

    def test_I2_action_is_bound_before_insert_returns_and_stop_cannot_claim(self):
        name,server,tool=self.mcp_fixture();self.allow([name]);t=self.claimed()
        ctx=ToolContext(user_id=self.uid,bot=db.get_bot(self.uid,self.bid));ctx.chat_execution=worker.Execution(t)
        original=action_store.insert;observed=[]
        def interleave(*a,**kw):
            aid=original(*a,**kw)
            observed.append(action_store.get(self.uid,aid)['chat_task_id'])
            with db.tx(immediate=True) as c:store.control(c,self.uid,self.bid,t['id'],{'expected_version':1,'control_request_id':'stop'})
            observed.append(action_store.claim_for_execution(self.uid,aid)[0])
            return aid
        with patch('verabot.services.actions.action_store.insert',interleave):actions.create_mcp_pending(ctx,server,tool,{'title':'x'})
        self.assertEqual(observed[0],t['id'])
        self.assertNotEqual(observed[1],'claimed')

    def test_I2_crash_inside_link_rolls_back_pending_insert(self):
        name,server,tool=self.mcp_fixture();self.allow([name]);t=self.claimed()
        ctx=ToolContext(user_id=self.uid,bot=db.get_bot(self.uid,self.bid));ctx.chat_execution=worker.Execution(t)
        with patch('verabot.db.chat_reply_store.bind_action',side_effect=RuntimeError('simulated process failure')):
            with self.assertRaises(RuntimeError):actions.create_mcp_pending(ctx,server,tool,{'title':'x'})
        with db.tx() as c:self.assertEqual(c.execute('SELECT COUNT(*) FROM pending_actions WHERE user_id=?',(self.uid,)).fetchone()[0],0)

    def test_I2_stop_and_clear_before_creation_leave_no_pending_action(self):
        name,server,tool=self.mcp_fixture();self.allow([name]);t=self.claimed()
        ctx=ToolContext(user_id=self.uid,bot=db.get_bot(self.uid,self.bid));ctx.chat_execution=worker.Execution(t)
        self.client.delete(f'/api/bots/{self.bid}/messages')
        try:actions.create_mcp_pending(ctx,server,tool,{'title':'x'})
        except (ValueError,store.ChatTaskError):pass
        with db.tx() as c:self.assertEqual(c.execute('SELECT COUNT(*) FROM pending_actions WHERE user_id=?',(self.uid,)).fetchone()[0],0)

    def test_I3_approved_content_restores_taint_cross_service_and_blocks_writes(self):
        name,server,tool=self.mcp_fixture();self.allow([name,'manage_reminder','ask_bot'])
        target=self.client.post('/api/bots',json={'name':'Target','accept_delegation':True}).json()['id']
        with db.tx() as c:c.execute('UPDATE bots SET delegate_to=? WHERE id=?',(json.dumps([target]),self.bid))
        self.submit();ran=[]
        async def write(ctx,**kw):ran.append('write');return {'ok':True}
        async def model(messages,*a,**k):
            tools=[m for m in messages if m['role']=='tool']
            if not tools:
                yield 'tool_calls',[{'id':'external','name':name,'arguments':'{}'},{'id':'write','name':'manage_reminder','arguments':'{}'},{'id':'delegate','name':'ask_bot','arguments':'{"bot_name":"Target","question":"x"}'}]
            else:yield 'delta','done'
        with patch('verabot.services.llm.stream_chat',model),patch.object(REGISTRY['manage_reminder'],'handler',write):
            asyncio.run(worker.process_one('w'))
            task=self.client.get(f'/api/bots/{self.bid}/chat/execution').json()['tasks'][0];aid=int(task['wait_id'].split(':')[1])
            with patch('verabot.services.actions.mcp.invoke',return_value={'code':'ok','content':'external content'}):
                self.assertEqual(self.client.post(f'/api/pending-actions/{aid}/confirm').status_code,200)
            with db.tx() as c:cp=store.decode_checkpoint(store.get(c,self.uid,self.bid,task['id'])['checkpoint_json'])
            self.assertTrue(cp['turn']['untrusted_tainted'])
            self.assertIn('Fixture',cp['turn']['mcp_read_servers'])
            self.assertEqual(cp['turn']['mcp_calls'],1)
            from verabot.services.mcp.policy import cross_server_warnings
            self.assertTrue(cross_server_warnings(set(cp['turn']['mcp_read_servers']),'Another server'))
            asyncio.run(worker.process_one('w'))
        self.assertEqual(ran,[])
        task=self.client.get(f'/api/bots/{self.bid}/chat/execution').json()['tasks'][0]
        results={t['id']:t['result'] for t in task['traces']}
        self.assertEqual(results['write']['code'],'external_needs_confirmation')
        self.assertEqual(results['delegate']['code'],'untrusted_tainted')

    def test_I4_resumed_tool_trace_and_future_protocol_have_one_identity(self):
        self.allow(['list_reminders']);self.claimed_wait_pending('wait','list_reminders')
        async def model(messages,*a,**k):yield 'delta','done'
        with patch('verabot.services.llm.stream_chat',model):asyncio.run(worker.process_one('w'))
        task=self.client.get(f'/api/bots/{self.bid}/chat/execution').json()['tasks'][0]
        self.assertEqual([t['id'] for t in task['traces']],['pending'])
        from verabot.agents.runtime import _history
        history,_=_history(self.uid,self.bid)
        calls=[tc['id'] for m in history for tc in m.get('tool_calls',[])]
        results=[m['tool_call_id'] for m in history if m['role']=='tool']
        self.assertEqual(calls,['pending']);self.assertEqual(results,['pending'])

    def test_I4_resumed_new_tool_trace_has_one_identity(self):
        self.allow(['list_reminders']);t=self.claimed()
        with db.tx(immediate=True) as c:
            cp={'messages':[{'role':'user','content':'original'}],'traces':[],'answer':'','round':1,'pending_calls':[]}
            store.save_checkpoint(c,t,cp);store.finish(c,t,'awaiting_user','question',[],wait_id='w')
            store.control(c,self.uid,self.bid,t['id'],{'client_request_id':'answer','expected_version':1,'wait_id':'w','message':'answer'},answer=True)
        async def model(messages,*a,**k):
            if any(m['role']=='tool' for m in messages):yield 'delta','done';return
            yield 'tool_calls',[{'id':'new','name':'list_reminders','arguments':'{}'}]
        with patch('verabot.services.llm.stream_chat',model):asyncio.run(worker.process_one('w'))
        task=self.client.get(f'/api/bots/{self.bid}/chat/execution').json()['tasks'][0]
        self.assertEqual([t['id'] for t in task['traces']],['new'])

    def test_I5_input_delete_finishes_surviving_output_and_detail_event(self):
        t=self.claimed()
        with db.tx(immediate=True) as c:store.save_partial(c,t,'partial',[])
        before=self.client.get(f'/api/bots/{self.bid}/chat/execution').json()['event_cursor']
        self.assertEqual(self.client.delete(f"/api/bots/{self.bid}/messages/{t['input_message_id']}").status_code,200)
        task=self.client.get(f'/api/bots/{self.bid}/chat/execution').json()['tasks'][0]
        self.assertEqual(task['state'],'stopped');self.assertEqual(task['message_status'],'stopped')
        self.assertGreater(task['publication_revision'],0);self.assertIn('partial',task['content'])
        events=store.events(self.uid,self.bid,before)
        self.assertTrue(any(e['event']=='task_updated' and e['data']['task_id']==t['id'] for e in events))
        with db.tx(immediate=True) as c:self.assertFalse(store.finish(c,t,'completed','late',[]))

    def test_I5_output_delete_remains_deleted_without_recreation(self):
        t=self.claimed()
        self.client.delete(f"/api/bots/{self.bid}/messages/{t['output_message_id']}")
        with db.tx(immediate=True) as c:
            self.assertFalse(store.finish(c,t,'completed','late',[]))
            self.assertIsNone(c.execute('SELECT 1 FROM messages WHERE id=?',(t['output_message_id'],)).fetchone())
        task=self.client.get(f'/api/bots/{self.bid}/chat/execution').json()['tasks'][0]
        self.assertEqual(task['state'],'stopped');self.assertEqual(task['message_status'],'deleted')

    def test_M1_first_unsaved_fragment_flushes_at_deadline_despite_offset(self):
        self.submit();clock=[0.0];flushed=[];original_sleep=asyncio.sleep;original_save=store.save_partial
        async def scenario():
            ready=asyncio.Event();finished=asyncio.Event();sleeps=[]
            async def sleep(delay):
                start=clock[0];sleeps.append(delay)
                if len(sleeps)==1:
                    clock[0]=.25;ready.set();await original_sleep(0)
                clock[0]=start+delay
                await original_sleep(0)
            async def model(*a,**k):
                await ready.wait()
                yield 'delta','x'*256
                clock[0]=.26
                yield 'delta','tail'
                await finished.wait()
            def save(c,t,text,traces):
                result=original_save(c,t,text,traces)
                if text.endswith('tail'):
                    flushed.append(clock[0]);finished.set()
                return result
            with patch('verabot.services.chat_tasks.worker.asyncio.sleep',sleep),patch('verabot.services.chat_tasks.worker.time.monotonic',side_effect=lambda:clock[0]),patch('verabot.services.llm.stream_chat',model),patch('verabot.services.chat_tasks.worker.store.save_partial',save):
                await worker.process_one('w')
        asyncio.run(scenario())
        self.assertTrue(flushed);self.assertLessEqual(flushed[0],1.26)

if __name__=='__main__':unittest.main()
