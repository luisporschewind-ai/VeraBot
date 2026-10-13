import json
import asyncio
import unittest
from unittest.mock import patch
from uuid import uuid4
from group_execution_test_support import GroupExecutionFixture,db
from verabot.db import group_execution_store as s,group_store
from verabot.services import group_routing as r,group_dispatch

class RoutingRepairTests(unittest.TestCase):
    def setUp(self):
        self.fx=GroupExecutionFixture()
        self.group=group_store.get_group(self.fx.user_id,self.fx.group_id)
        self.group['members'][0]['name']='研究员';self.group['members'][1]['name']='写作者'
    def request(self, **kw): return {'client_request_id':str(uuid4()),'message':'完整目标','target_member_ids':[],'everyone':False,'attachment_ids':[], **kw}
    def claim(self): return s.claim_next('test','2026-10-13T00:00:00+00:00')
    def awaiting(self):
        t=s.create_input(self.fx.user_id,self.fx.group_id,self.request());p=self.claim()
        s.apply_route(p['id'],p['lease_token'],p['version'],{'intent':'clarify','speaker_member_ids':[self.fx.member_ids[0]],'goal':'完整目标','missing_information':['地点']})
        m=self.claim();s.commit_step(m['id'],m['lease_token'],m['version'],{'status':'completed','content':'是否北京？','action':{'kind':'await_user','missing_information':['地点']}})
        return s.execution_snapshot(self.fx.user_id,self.fx.group_id)
    def test_running_supplement_preserves_task_owner_and_goal_until_classified(self):
        t=s.create_input(self.fx.user_id,self.fx.group_id,self.request());p=self.claim()
        s.apply_route(p['id'],p['lease_token'],p['version'],{'intent':'respond','speaker_member_ids':[self.fx.member_ids[1]],'goal':'完整目标','missing_information':[]})
        t2=group_dispatch.submit(self.fx.user_id,self.fx.group_id,self.request(message='预算100元',expected_task_id=t['id'],expected_version=1))
        self.assertEqual(t2['id'],t['id']);self.assertEqual(t2['version'],2)
        self.assertEqual(t2['goal'],'完整目标');self.assertEqual(t2['owner_member_id'],self.fx.member_ids[1])
    def test_answer_does_not_replace_original_goal_and_context_keeps_all_answers(self):
        x=self.awaiting();t=x['task']
        req=self.request(message='好的',expected_task_id=t['id'],expected_version=t['version'],clarification_id=x['clarification']['id'])
        s.create_input(self.fx.user_id,self.fx.group_id,req)
        t,cl,h,fair=s.routing_context(self.fx.user_id,self.fx.group_id,t['id'])
        self.assertEqual(t['goal'],'完整目标')
        self.assertIn('好的',json.dumps(t,ensure_ascii=False))
    def test_replace_keeps_classifier_selection_and_creates_independent_task(self):
        x=self.awaiting();t=x['task'];b=self.fx.member_ids[1]
        req=self.request(message='换个话题，写文章',expected_task_id=t['id'],expected_version=t['version'],clarification_id=x['clarification']['id'])
        s.create_input(self.fx.user_id,self.fx.group_id,req);p=self.claim()
        cl=s.routing_context(self.fx.user_id,self.fx.group_id,t['id'])[1]
        d=r.parse_decision(json.dumps({'intent':'replace','speaker_member_ids':[b],'goal':'写文章','missing_information':[]}),self.group,req,cl,{})
        self.assertEqual(d['speaker_member_ids'],[b]);self.assertEqual(d['missing_information'],[])
        s.apply_route(p['id'],p['lease_token'],p['version'],d)
        new=s.execution_snapshot(self.fx.user_id,self.fx.group_id)['task']
        self.assertNotEqual(new['id'],t['id']);self.assertEqual(new['owner_member_id'],b)
    def test_natural_name_overrides_clarification_owner(self):
        cl={'id':1,'owner_member_id':self.fx.member_ids[0],'original_request':'目标'}
        b=self.fx.member_ids[1]
        d=r.parse_decision(json.dumps({'intent':'respond','speaker_member_ids':[b],'goal':'写文章','missing_information':[]}),self.group,self.request(message='写作者，请你处理'),cl,{})
        self.assertEqual(d['speaker_member_ids'],[b])
    def test_old_reply_resolves_member_outside_recent_window(self):
        x=self.awaiting();old=x['clarification']['latest_question_message_id'];a=self.fx.member_ids[0]
        with db.tx() as c:
            for _ in range(30): c.execute("INSERT INTO chat_group_messages(group_id,user_id,turn_id,role,content,status,created_at) SELECT group_id,user_id,turn_id,'user','历史','completed','now' FROM chat_group_messages WHERE id=?",(old,))
        task,cl,h,fair=s.routing_context(self.fx.user_id,self.fx.group_id,x['task']['id'])
        async def invalid(*args,**kw): return 'invalid',None
        with patch.object(r.llm,'complete_json',invalid):
            d=asyncio.run(r.resolve(self.fx.user_id,self.group,self.request(message='请继续',reply_to_message_id=old),None,h,None,{}))
        self.assertEqual(d['speaker_member_ids'],[a]);self.assertFalse(d['usage_unknown'])

if __name__=='__main__':unittest.main()
