import asyncio
import json
import unittest
from uuid import uuid4
from group_execution_test_support import GroupExecutionFixture,db
from verabot.db import group_execution_store as s,group_store
from verabot.services import group_actions,group_routing
from verabot.agents import group_context

class ReviewRepairTests(unittest.TestCase):
    def setUp(self): self.fx=GroupExecutionFixture()
    def claim(self):return s.claim_next('test','2026-10-13T00:00:00+00:00')
    def request(self,**kw):return {'client_request_id':str(uuid4()),'message':'完整目标','target_member_ids':[],**kw}
    def prepare(self,targets=None,**kw):
        t=s.create_input(self.fx.user_id,self.fx.group_id,self.request(**kw));r=self.claim()
        s.apply_route(r['id'],r['lease_token'],r['version'],{'intent':'respond','speaker_member_ids':targets or self.fx.member_ids,'goal':'完整目标','missing_information':[]})
        return t
    def finish(self,step,**result):s.commit_step(step['id'],step['lease_token'],step['version'],{'status':'completed','content':'完成','action':{'kind':'completed'},**result})
    def test_waiting_answer_keeps_remaining_speakers(self):
        t=self.prepare();a=self.claim();self.finish(a,content='什么场景？',action={'kind':'await_user','missing_information':['场景']})
        x=s.execution_snapshot(self.fx.user_id,self.fx.group_id)
        s.create_input(self.fx.user_id,self.fx.group_id,self.request(message='会议',expected_task_id=t['id'],expected_version=1,clarification_id=x['clarification']['id']))
        r=self.claim();s.apply_route(r['id'],r['lease_token'],r['version'],{'intent':'continue','speaker_member_ids':[self.fx.member_ids[0]],'goal':'会议意见','missing_information':[]})
        self.finish(self.claim());b=self.claim()
        self.assertIsNotNone(b);self.assertEqual(b['member_id'],self.fx.member_ids[1])
    def test_retry_keeps_remaining_speakers_in_order(self):
        # 仅无可用正文的失败消息可公开重试（有正文时对外 completed）。
        t=self.prepare();a=self.claim();self.finish(a,status='failed',content='',action=None)
        s.retry_failed(self.fx.user_id,self.fx.group_id,a['message_id'],str(uuid4()),1)
        retried=self.claim();self.assertEqual(retried['member_id'],self.fx.member_ids[0]);self.finish(retried)
        b=self.claim();self.assertIsNotNone(b);self.assertEqual(b['member_id'],self.fx.member_ids[1])
    def test_deleted_group_step_reuse_does_not_reuse_call_identity(self):
        t=self.prepare([self.fx.member_ids[0]]);a=self.claim();call=s.begin_member_call(a['id'],a['lease_token'],a['version'])
        s.record_call(call,self.fx.user_id,self.fx.group_id,t['id'],a['id'],'group_chat',{'total_tokens':2},False);self.finish(a,usage_recorded=True)
        group_store.delete_group(self.fx.user_id,self.fx.group_id)
        new=group_store.create_group(self.fx.user_id,'新群',self.fx.bot_ids);self.fx.group_id=new['id'];self.fx.member_ids=[m['id'] for m in new['members']]
        t2=self.prepare([self.fx.member_ids[0]]);a2=self.claim();call2=s.begin_member_call(a2['id'],a2['lease_token'],a2['version'])
        self.assertNotEqual(call,call2)
    def test_new_request_after_failed_clarifier_releases_old_lock(self):
        t=s.create_input(self.fx.user_id,self.fx.group_id,self.request());r=self.claim()
        decision={'intent':'clarify','speaker_member_ids':[self.fx.member_ids[0]],'goal':'目标','missing_information':['目的']}
        s.apply_route(r['id'],r['lease_token'],r['version'],decision);a=self.claim();self.finish(a,status='failed',action=None)
        new=s.create_input(self.fx.user_id,self.fx.group_id,self.request(message='新问题'));r2=self.claim()
        self.assertTrue(s.apply_route(r2['id'],r2['lease_token'],r2['version'],decision))
        with db.tx() as c:self.assertEqual(c.execute("SELECT COUNT(*) FROM chat_group_clarifications WHERE status IN ('active','awaiting_user')").fetchone()[0],1)
    def test_retry_older_failure_is_the_current_execution(self):
        t=self.prepare([self.fx.member_ids[0]]);a=self.claim();self.finish(a,status='failed',content='',action=None)
        newer=self.prepare([self.fx.member_ids[1]]);self.finish(self.claim())
        s.retry_failed(self.fx.user_id,self.fx.group_id,a['message_id'],str(uuid4()),1)
        self.assertEqual(s.execution_snapshot(self.fx.user_id,self.fx.group_id)['task']['id'],t['id'])
    def test_retry_cannot_create_second_active_task(self):
        t=self.prepare([self.fx.member_ids[0]]);a=self.claim();self.finish(a,status='failed',content='',action=None)
        newer=self.prepare([self.fx.member_ids[1]])
        with self.assertRaises(s.GroupExecutionError) as error:s.retry_failed(self.fx.user_id,self.fx.group_id,a['message_id'],str(uuid4()),1)
        self.assertEqual(error.exception.status,409)
    def test_retry_rejects_failed_step_when_message_has_usable_content(self):
        t=self.prepare([self.fx.member_ids[0]]);a=self.claim();self.finish(a,status='failed',content='已有可用正文',action=None)
        with db.tx() as c:
            self.assertEqual(c.execute("SELECT status FROM chat_group_messages WHERE id=?",(a['message_id'],)).fetchone()[0],'completed')
        with self.assertRaises(s.GroupExecutionError) as error:s.retry_failed(self.fx.user_id,self.fx.group_id,a['message_id'],str(uuid4()),1)
        self.assertEqual(error.exception.status,409)
    def test_retry_completed_message_returns_domain_conflict(self):
        t=self.prepare([self.fx.member_ids[0]]);a=self.claim();self.finish(a)
        with self.assertRaises(s.GroupExecutionError) as error:s.retry_failed(self.fx.user_id,self.fx.group_id,a['message_id'],str(uuid4()),1)
        self.assertEqual(error.exception.status,409)
    def test_explicit_old_reply_content_is_provided_to_member(self):
        t=self.prepare([self.fx.member_ids[0]]);a=self.claim();self.finish(a,content='是否采用火星方案XYZ？')
        with db.tx() as c:
            for _ in range(30):c.execute("INSERT INTO chat_group_messages(group_id,user_id,turn_id,role,content,status,created_at) VALUES (?,?,?,'user','较新记录','completed','now')",(self.fx.group_id,self.fx.user_id,a['turn_id']))
        req=self.request(message='好的',reply_to_message_id=a['message_id'])
        new=s.create_input(self.fx.user_id,self.fx.group_id,req);r=self.claim()
        task,cl,h,f=s.routing_context(self.fx.user_id,self.fx.group_id,new['id'])
        decision=asyncio.run(group_routing.resolve(self.fx.user_id,group_store.get_group(self.fx.user_id,self.fx.group_id),r['input'],task,h,cl,f))
        s.apply_route(r['id'],r['lease_token'],r['version'],decision);member=self.claim()
        context=group_context.build_execution(self.fx.user_id,self.fx.group_id,new,member,remaining_calls=6)
        self.assertIn('火星方案XYZ',json.dumps(context,ensure_ascii=False))

if __name__=='__main__':unittest.main()
