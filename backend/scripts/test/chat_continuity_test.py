"""Isolated behavioral contract: accepted inputs and sparse publication reads."""
import asyncio
import json
import unittest
from unittest.mock import patch
import primary_bot_test as support
from verabot import db

class ContinuityTests(unittest.TestCase):
    def setUp(self):
        db.init_db()
        with db.tx() as c:c.execute("DELETE FROM chat_groups")
        support.PrimaryTests.setUp(self)
    tearDown = support.PrimaryTests.tearDown

    def submit(self, key='one', message='hello'):
        r = self.client.post(f'/api/bots/{self.bid}/chat/inputs', json={
            'client_request_id': key, 'message': message, 'expected_generation': 1})
        self.assertIn(r.status_code, (200, 202), r.text)
        return r.json()

    def test_atomic_receipt_replay_conflict_and_isolation(self):
        first = self.submit()
        self.assertEqual(self.submit()['task']['id'], first['task']['id'])
        self.assertEqual(self.client.post(f'/api/bots/{self.bid}/chat/inputs', json={
            'client_request_id':'one','message':'different','expected_generation':1}).status_code,409)
        self.assertEqual(self.client.get(f'/api/bots/{self.foreign}/chat/execution').status_code,404)
        with db.tx() as c:
            self.assertEqual(c.execute('SELECT COUNT(*) FROM messages WHERE bot_id=?',(self.bid,)).fetchone()[0],2)
        self.assertEqual(self.client.get(f'/api/bots/{self.bid}/chat/inputs/one').json(),first)

    def test_detached_worker_stable_output_queue_and_context_boundary(self):
        one=self.submit('one','first'); two=self.submit('two','second')
        prompts=[]
        async def model(messages,*args,**kwargs):
            prompts.append(messages)
            yield 'delta','reply'
            yield 'usage',{'total_tokens':3}
        from verabot.services.chat_tasks import worker
        with patch('verabot.services.llm.stream_chat',model):
            asyncio.run(worker.process_one('fixture'))
            asyncio.run(worker.process_one('fixture'))
        self.assertNotIn('second',json.dumps(prompts[0]))
        self.assertIn('reply',json.dumps(prompts[1]))
        data=self.client.get(f'/api/bots/{self.bid}/chat/execution').json()
        self.assertTrue(all(t['state']=='completed' for t in data['tasks']))
        self.assertEqual(data['tasks'][0]['assistant_message_id'],one['assistant_message_id'])
        with db.tx() as c:self.assertEqual(c.execute('SELECT COUNT(*) FROM messages WHERE bot_id=?',(self.bid,)).fetchone()[0],4)

    def test_sparse_reads_and_final_revision_after_partial(self):
        from verabot.db import chat_reply_store as s
        one=self.submit('one');two=self.submit('two')
        with db.tx(immediate=True) as c:
            task=s.claim_next(c,'w')
            s.save_partial(c,task,'partial',[])
        mid=one['assistant_message_id']
        read=f'/api/conversations/private/{self.bid}/read'
        self.assertEqual(self.client.post(read,json={'generation':1,'messages':[{'message_id':mid,'publication_revision':1}]}).status_code,409)
        with db.tx(immediate=True) as c:s.finish(c,task,'completed','done',[])
        with db.tx(immediate=True) as c:
            task=s.claim_next(c,'w');s.finish(c,task,'completed','later',[])
        self.assertEqual(self.client.post(read,json={'generation':1,'messages':[{'message_id':two['assistant_message_id'],'publication_revision':1}]}).status_code,200)
        a=self.client.get('/api/conversations/activity').json()['conversations'][0]
        self.assertEqual(a['unread_messages'],[{'message_id':mid,'publication_revision':1}])

    def test_stop_and_clear_fence_late_result(self):
        from verabot.db import chat_reply_store as s
        one=self.submit()
        with db.tx(immediate=True) as c:task=s.claim_next(c,'w')
        stop=f"/api/bots/{self.bid}/chat/tasks/{task['id']}/stop"
        body={'expected_version':task['version'],'control_request_id':'stop-1'}
        self.assertEqual(self.client.post(stop,json=body).status_code,200)
        self.assertEqual(self.client.post(stop,json=body).status_code,200)
        with db.tx(immediate=True) as c:self.assertFalse(s.finish(c,task,'completed','late',[]))
        self.client.delete(f'/api/bots/{self.bid}/messages')
        self.assertEqual(self.client.get(f'/api/bots/{self.bid}/chat/execution').json()['generation'],2)
        with db.tx(immediate=True) as c:self.assertFalse(s.finish(c,task,'completed','late',[]))
        self.assertEqual(self.client.get(f'/api/bots/{self.bid}/messages').json()['messages'],[])

    def test_migration_idempotent_and_legacy_history_hidden_placeholder(self):
        self.submit(); db.init_db();db.init_db()
        self.assertEqual(len(self.client.get(f'/api/bots/{self.bid}/messages').json()['messages']),1)
        self.assertEqual(self.client.post(f'/api/bots/{self.bid}/chat',json={'message':'legacy'}).status_code,409)

    def test_expired_lease_preserves_partial_and_never_replays_unknown_tool(self):
        from verabot.db import chat_reply_store as s
        self.submit()
        with db.tx(immediate=True) as c:
            task=s.claim_next(c,'w');s.save_partial(c,task,'partial',[])
            s.start_tool(c,task,{'id':'call1','name':'create_reminder','arguments':'{}'})
            c.execute("UPDATE chat_reply_tasks SET lease_expires_at='2000-01-01' WHERE id=?",(task['id'],))
            s.recover(c)
            self.assertIsNone(s.claim_next(c,'w'))
        t=self.client.get(f'/api/bots/{self.bid}/chat/execution').json()['tasks'][0]
        self.assertEqual(t['state'],'interrupted');self.assertIn('partial',t['content'])

    def test_sync_history_includes_status_publication_and_generation(self):
        one=self.submit()
        response=self.client.get(f'/api/bots/{self.bid}/messages/sync').json()
        assistant=[m for m in response['messages'] if m['id']==one['assistant_message_id']][0]
        self.assertEqual(assistant['message_status'],'queued')
        self.assertEqual(assistant['publication_revision'],0)
        self.assertEqual(response['generation'],1)

    def test_approval_resume_real_result_and_final_new_publication(self):
        from verabot.services import actions
        from verabot.db import mcp_store
        from verabot.services.chat_tasks import worker
        name='mcp__fixture__write'
        server=mcp_store.insert_server(self.uid,dict(slug='fixture',catalog_id='fixture',name='Fixture',transport='http',url='http://127.0.0.1:1',trust='test',auth='none'),'connected')
        mcp_store.upsert_tool(self.uid,server['id'],dict(full_name=name,mcp_name='write',description='fixture',input_schema={'type':'object'},def_hash='hash',risk='write'))
        with db.tx() as c:c.execute('UPDATE bots SET allowed_tools=? WHERE id=?',(json.dumps([name]),self.bid))
        one=self.submit()
        calls=[]
        async def model(messages,*a,**k):
            if not any(m['role']=='tool' for m in messages):
                yield 'tool_calls',[{'id':'c1','name':name,'arguments':'{"title":"x"}'},{'id':'c2','name':'list_bots','arguments':'{}'}]
            else:
                self.assertIn('resource-123',json.dumps(messages))
                tc=next(m for m in messages if m.get('tool_calls'))['tool_calls']
                self.assertEqual(len([m for m in messages if m['role']=='tool']),len(tc))
                yield 'delta','saved'
        async def dispatch(ctx,n,args,call_id=None):
            calls.append(n)
            if n==name:return actions.create_mcp_pending(ctx,server,mcp_store.get_tool_by_full_name(self.uid,name),json.loads(args))
            return {'bots':[]}
        with patch('verabot.services.llm.stream_chat',model),patch('verabot.agents.runtime.dispatch',dispatch):
            asyncio.run(worker.process_one('w'))
            t=self.client.get(f'/api/bots/{self.bid}/chat/execution').json()['tasks'][0]
            self.assertEqual(t['state'],'awaiting_approval')
            read=f'/api/conversations/private/{self.bid}/read'
            self.assertEqual(self.client.post(read,json={'generation':1,'messages':[{'message_id':one['assistant_message_id'],'publication_revision':1}]}).status_code,200)
            aid=int(t['wait_id'].split(':')[1])
            with patch('verabot.services.actions.mcp.invoke',return_value={'code':'ok','content':'resource-123'}):
                self.assertEqual(self.client.post(f'/api/pending-actions/{aid}/confirm').status_code,200)
                self.assertEqual(self.client.post(f'/api/pending-actions/{aid}/confirm').status_code,409)
            asyncio.run(worker.process_one('w'))
        t=self.client.get(f'/api/bots/{self.bid}/chat/execution').json()['tasks'][0]
        self.assertEqual(t['state'],'completed')
        self.assertGreater(t['publication_revision'],1)
        self.assertEqual(calls.count(name),1)
        self.assertEqual(self.client.get('/api/conversations/activity').json()['conversations'][0]['unread_count'],1)

    def test_owned_old_generation_result_not_delivered_after_clear(self):
        from verabot.db import owned_task_store as s
        from verabot.services.owned_tasks import delivery
        self.client.patch('/api/primary-bot',json={'primary_bot_id':self.bid,'active_enabled':True,'expected_version':1})
        t=self.client.post('/api/owned-tasks',headers={'Idempotency-Key':'o'},json={'bot_id':self.bid,'goal':'report','completion_criteria':'done'}).json()
        with db.tx(immediate=True) as c:
            step=s.claim_next(c,'w',db.now_iso())
        self.client.delete(f'/api/bots/{self.bid}/messages')
        with db.tx(immediate=True) as c:s.commit_step(c,step,{'action':'completed','text':'old'})
        delivery.flush()
        self.assertEqual(self.client.get(f'/api/bots/{self.bid}/messages').json()['messages'],[])

    def test_owned_notification_failure_does_not_rollback_publication(self):
        from verabot.db import owned_task_store as s
        from verabot.services.owned_tasks import delivery
        self.client.patch('/api/primary-bot',json={'primary_bot_id':self.bid,'active_enabled':True,'expected_version':1})
        self.client.post('/api/owned-tasks',headers={'Idempotency-Key':'o'},json={'bot_id':self.bid,'goal':'report','completion_criteria':'done'})
        with db.tx(immediate=True) as c:
            step=s.claim_next(c,'w',db.now_iso());s.commit_step(c,step,{'action':'completed','text':'result'})
        with patch('verabot.services.owned_tasks.delivery.notify',side_effect=RuntimeError('fixture notification failure')):delivery.flush()
        self.assertEqual(self.client.get('/api/conversations/activity').json()['conversations'][0]['unread_count'],1)

    def test_wait_releases_slot_answer_is_bound_and_idempotent(self):
        from verabot.services.chat_tasks import worker
        from verabot.db import chat_reply_store as s
        one=self.submit();two=self.submit('two','independent')
        with db.tx(immediate=True) as c:
            t=s.claim_next(c,'w')
            cp={'messages':[{'role':'user','content':'hello'}],'answer':'','traces':[],'round':1}
            c.execute('UPDATE chat_reply_tasks SET checkpoint_json=? WHERE id=?',(s.encode_checkpoint(cp),t['id']))
            s.finish(c,t,'awaiting_user','which week?',[],wait_id='w1')
            other=s.claim_next(c,'w');self.assertEqual(other['id'],two['task']['id'])
            s.finish(c,other,'completed','independent answer',[])
        url=f"/api/bots/{self.bid}/chat/tasks/{t['id']}/inputs"
        body={'client_request_id':'a','expected_version':1,'wait_id':'wrong','message':'this week'}
        self.assertEqual(self.client.post(url,json=body).status_code,409)
        body['wait_id']='w1'
        answer=self.client.post(url,json=body)
        self.assertEqual(answer.status_code,200)
        self.assertIsInstance(answer.json()['answer_message_id'],int)
        self.assertEqual(self.client.post(url,json=body).json(),answer.json())
        self.assertEqual(self.client.post(url,json=body|{'client_request_id':'new'}).status_code,409)

    def test_stopped_runtime_does_not_finalize_or_postprocess(self):
        from verabot.services.chat_tasks import worker
        from verabot.db import chat_reply_store as s
        one=self.submit()
        async def model(*a,**k):
            yield 'delta','partial'
            with db.tx(immediate=True) as c:
                t=s.get(c,self.uid,self.bid,one['task']['id'])
                s.control(c,self.uid,self.bid,t['id'],{'expected_version':t['version'],'control_request_id':'stop'})
            yield 'delta','late'
        with patch('verabot.services.llm.stream_chat',model),patch('verabot.agents.runtime.memory.mark_used') as mark:
            asyncio.run(worker.process_one('w'));mark.assert_not_called()
        t=self.client.get(f'/api/bots/{self.bid}/chat/execution').json()['tasks'][0]
        self.assertEqual(t['state'],'stopped');self.assertNotIn('late',t['content'])
        with db.tx() as c:self.assertEqual(c.execute('SELECT COUNT(*) FROM messages WHERE bot_id=?',(self.bid,)).fetchone()[0],2)

    def test_legacy_messages_after_clear_use_current_generation(self):
        self.client.delete(f'/api/bots/{self.bid}/messages')
        db.add_message(self.uid,self.bid,'assistant','new legacy reply')
        a=self.client.get('/api/conversations/activity').json()['conversations'][0]
        self.assertEqual(a['unread_count'],1)
        self.assertEqual(a['latest_message']['content'],'new legacy reply')

    def test_group_history_exposes_publication_and_read(self):
        from verabot.db import group_store
        second=self.client.post('/api/bots',json={'name':'second'}).json()['id']
        group=group_store.create_group(self.uid,'g',[self.bid,second])
        with db.tx() as c:
            turn={'id':c.execute("INSERT INTO chat_group_turns(user_id,group_id,client_request_id,request_hash,mode,status,created_at) VALUES(?,?,'fixture','hash','single','completed','now')",(self.uid,group['id'])).lastrowid}
            mid=c.execute("INSERT INTO chat_group_messages(user_id,group_id,turn_id,role,content,status,created_at) VALUES(?,?,?,'bot','question','completed','now')",(self.uid,group['id'],turn['id'])).lastrowid
        m=group_store.list_messages(self.uid,group['id'])['messages'][-1]
        self.assertEqual(m['publication_revision'],1)
        self.assertEqual(m['generation'],1)
        self.assertEqual(self.client.post(f"/api/conversations/group/{group['id']}/read",json={'generation':1,'messages':[{'message_id':mid,'publication_revision':1}]}).status_code,200)
        a=self.client.get('/api/conversations/activity').json()['conversations'][-1]
        self.assertEqual(a['unread_count'],0)

    def test_durable_preserves_style_proposal(self):
        from verabot.services.chat_tasks import worker
        self.submit(message='请简洁一点')
        async def model(*a,**k):yield 'delta','ok'
        with patch('verabot.services.llm.stream_chat',model),patch('verabot.agents.runtime.memory_style.match_style',return_value='cue'),patch('verabot.agents.runtime.memory.propose_style',return_value={'status':'proposed','id':123}) as propose,patch('verabot.agents.runtime.memory_style.trace_for',return_value={'id':'s','name':'style','result':{'id':123}}):
            asyncio.run(worker.process_one('w'))
            self.assertEqual(propose.call_count,1)
        t=self.client.get(f'/api/bots/{self.bid}/chat/execution').json()['tasks'][0]
        self.assertEqual(t['traces'][0]['name'],'style')

    def test_completed_tool_id_reuse_with_different_arguments_conflicts(self):
        from verabot.db import chat_reply_store as s
        self.submit()
        with db.tx(immediate=True) as c:
            t=s.claim_next(c,'w');call={'id':'same','name':'list_bots','arguments':'{}'}
            s.start_tool(c,t,call);s.complete_tool(c,t,call,{'bots':[]})
            with self.assertRaises(s.ChatTaskError):s.start_tool(c,t,call|{'arguments':'{"x":1}'})

    def test_transient_provider_connection_retry_is_bounded_before_output(self):
        import httpx
        from verabot.services.chat_tasks import worker
        self.submit();calls=[]
        async def model(*a,**k):
            calls.append(1)
            if len(calls)==1:raise httpx.ConnectError('fixture connection failure')
            yield 'delta','recovered'
        with patch('verabot.services.llm.stream_chat',model):asyncio.run(worker.process_one('w'))
        t=self.client.get(f'/api/bots/{self.bid}/chat/execution').json()['tasks'][0]
        self.assertEqual(t['state'],'completed');self.assertEqual(len(calls),2)

    def test_attachment_replay_binds_once_and_durable_reads_original_attachment(self):
        from PIL import Image
        import io
        buf=io.BytesIO();Image.new('RGB',(2,2),'blue').save(buf,format='PNG')
        aid=self.client.post('/api/attachments',files={'file':('image.png',buf.getvalue(),'image/png')},data={'bot_id':str(self.bid)}).json()['id']
        body={'client_request_id':'a','expected_generation':1,'message':'image','attachment_ids':[aid]}
        one=self.client.post(f'/api/bots/{self.bid}/chat/inputs',json=body)
        self.assertEqual(one.status_code,202)
        two=self.client.post(f'/api/bots/{self.bid}/chat/inputs',json=body)
        self.assertEqual(two.status_code,200);self.assertEqual(one.json(),two.json())
        with db.tx() as c:
            row=c.execute('SELECT message_id,status FROM attachments WHERE id=?',(aid,)).fetchone()
            self.assertEqual(row['message_id'],one.json()['user_message_id']);self.assertEqual(row['status'],'attached')
        page=self.client.get(f'/api/bots/{self.bid}/messages/sync').json()
        self.assertEqual(page['messages'][0]['attachments'][0]['id'],aid)

    def test_old_history_migration_creates_read_baseline_without_inbox_change(self):
        from verabot.db.migrations.v030_chat_continuity import migrate
        mid=db.add_message(self.uid,self.bid,'assistant','old')
        with db.tx(immediate=True) as c:
            c.execute('DELETE FROM message_publications');c.execute('DELETE FROM message_read_receipts')
            migrate(c,29);migrate(c,30)
        a=self.client.get('/api/conversations/activity').json()['conversations'][0]
        self.assertEqual(a['unread_count'],0)
        db.add_message(self.uid,self.bid,'assistant','new')
        self.assertEqual(self.client.get('/api/conversations/activity').json()['conversations'][0]['unread_count'],1)

    def test_v30_upgrade_saves_sqlite_backup(self):
        from pathlib import Path
        from verabot.db.database import DB_PATH
        with db.tx() as c:c.execute("UPDATE schema_meta SET value='29' WHERE key='version'")
        before=set(Path(DB_PATH).parent.glob(Path(DB_PATH).name+'.bak-before-v30-*'))
        db.init_db()
        after=set(Path(DB_PATH).parent.glob(Path(DB_PATH).name+'.bak-before-v30-*'))
        self.assertEqual(len(after-before),1)

    def test_postprocessing_failure_does_not_fail_published_answer(self):
        from verabot.services.chat_tasks import worker
        self.submit()
        async def model(*a,**k):yield 'delta','answer'
        with patch('verabot.services.llm.stream_chat',model),patch('verabot.db.chat_reply_store.postprocess',side_effect=RuntimeError('fixture postprocess failure')):
            asyncio.run(worker.process_one('w'))
        t=self.client.get(f'/api/bots/{self.bid}/chat/execution').json()['tasks'][0]
        self.assertEqual(t['state'],'completed');self.assertEqual(t['content'],'answer')

    def test_deleted_bot_cancels_linked_pending_action(self):
        from verabot.db import chat_reply_store as s,bot_store
        self.submit()
        with db.tx(immediate=True) as c:
            t=s.claim_next(c,'w')
            aid=c.execute("INSERT INTO pending_actions(user_id,bot_id,kind,payload_enc,payload_hash,status,created_at,expires_at,chat_task_id,chat_task_version) VALUES (?,?,'mcp_tool_call',X'00','hash','pending','now','2999-01-01',?,?)",(self.uid,self.bid,t['id'],t['version'])).lastrowid
            bot_store.delete(c,self.uid,self.bid)
            self.assertEqual(c.execute('SELECT status FROM pending_actions WHERE id=?',(aid,)).fetchone()[0],'cancelled')

    def test_legacy_reservation_and_new_submission_cannot_double_execute(self):
        from verabot.db import chat_reply_store as s
        with db.tx(immediate=True) as c:token=s.reserve_legacy(c,self.uid,self.bid)
        self.assertEqual(self.client.post(f'/api/bots/{self.bid}/chat/inputs',json={'client_request_id':'one','message':'new','expected_generation':1}).status_code,409)
        with db.tx(immediate=True) as c:s.release_legacy(c,self.uid,self.bid,token)
        self.submit()
        with db.tx(immediate=True) as c:
            with self.assertRaises(s.ChatTaskError):s.reserve_legacy(c,self.uid,self.bid)

    def test_wait_checkpoint_preserves_reminder_dedup_and_taint_limits(self):
        from verabot.services.chat_tasks.worker import Execution
        from verabot.tools.registry import TurnState
        from verabot.db import chat_reply_store as s
        self.submit()
        with db.tx(immediate=True) as c:t=s.claim_next(c,'w')
        e=Execution(t);turn=TurnState();turn.reminder_created={('title','due'):{'id':5}};turn.untrusted_tainted=True;turn.delegations=2
        e.checkpoint_save([{'role':'user','content':'x'}],turn,[],'',{},1)
        with db.tx() as c:fresh=s.get(c,self.uid,self.bid,t['id'])
        restored=Execution(fresh).restore([],TurnState())[1]
        self.assertEqual(restored.reminder_created,turn.reminder_created)
        self.assertTrue(restored.untrusted_tainted);self.assertEqual(restored.delegations,2)

if __name__=='__main__':unittest.main()
