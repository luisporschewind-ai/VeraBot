import json
import unittest
from uuid import uuid4
from group_execution_test_support import GroupExecutionFixture, db
from verabot.db import group_execution_store as store
from verabot.services import group_actions
from verabot.agents import group_context

class StateRepairTests(unittest.TestCase):
    def setUp(self): self.fx=GroupExecutionFixture()
    def route(self, targets):
        task=store.create_input(self.fx.user_id,self.fx.group_id,{'client_request_id':str(uuid4()),'message':'完整目标','target_member_ids':targets})
        step=store.claim_next('test','2026-10-13T00:00:00+00:00')
        store.apply_route(step['id'],step['lease_token'],step['version'],{'intent':'respond','speaker_member_ids':targets,'goal':'完整目标','missing_information':[]})
        return task
    def test_all_selected_members_finish_in_order(self):
        task=self.route(self.fx.member_ids[::-1])
        actual=[]
        for _ in range(2):
            step=store.claim_next('test','2026-10-13T00:00:00+00:00')
            self.assertIsNotNone(step,'first reply must not finalize queued siblings')
            actual.append(step['member_id'])
            store.commit_step(step['id'],step['lease_token'],step['version'],{'status':'completed','content':'意见','action':{'kind':'completed'}})
        self.assertEqual(actual,self.fx.member_ids[::-1])
        self.assertEqual(store.snapshot(self.fx.user_id,self.fx.group_id,task['id'])['state'],'completed')
    def test_nested_consult_and_handoff_preserve_return_stack(self):
        task={'id':1,'goal':'完整目标','owner_member_id':10}
        first={'id':1,'member_id':10,'input':{}}
        b=group_actions.next_steps(task,first,{'kind':'consult','target_member_id':20,'goal':'研究','completion_criteria':'列出来源'})[0]
        c=group_actions.next_steps(task,{'id':2,'member_id':20,'input':b,'consult_return_step_id':1},{'kind':'consult','target_member_id':30,'goal':'校验'})[0]
        self.assertEqual(c['member_id'],30)
        back_b=group_actions.next_steps(task,{'id':3,'member_id':30,'input':c,'consult_return_step_id':2},{'kind':'completed','result':'校验完'})[0]
        self.assertEqual(back_b['member_id'],20)
        back_a=group_actions.next_steps(task,{'id':4,'member_id':20,'input':back_b},{'kind':'completed','result':'研究完'})[0]
        self.assertEqual(back_a['member_id'],10)
        d=group_actions.next_steps(task,{'id':2,'member_id':20,'input':b,'consult_return_step_id':1},{'kind':'handoff','target_member_id':30,'goal':'代为研究'})[0]
        self.assertEqual(d['member_id'],30)
        self.assertEqual(group_actions.next_steps(task,{'id':3,'member_id':30,'input':d},{'kind':'completed'})[0]['member_id'],10)
    def test_nested_consultation_is_actually_scheduled_by_store(self):
        with db.tx() as c:
            bot=c.execute("INSERT INTO bots(user_id,name,created_at) VALUES (?,'C','now')",(self.fx.user_id,)).lastrowid
            third=c.execute("INSERT INTO chat_group_members(group_id,user_id,bot_id,position,name_snapshot,appearance_snapshot) VALUES (?,?,?,2,'C','{}')",(self.fx.group_id,self.fx.user_id,bot)).lastrowid
        task=self.route([self.fx.member_ids[0]])
        for target,goal in ((self.fx.member_ids[1],'研究'),(third,'校验')):
            step=store.claim_next('test','2026-10-13T00:00:00+00:00')
            action={'kind':'consult','target_member_id':target,'goal':goal,'result':'已有资料'}
            plan=group_actions.next_steps(task,step,action)
            store.commit_step(step['id'],step['lease_token'],step['version'],{'status':'completed','content':'咨询','action':action,'next_steps':plan})
        third_step=store.claim_next('test','2026-10-13T00:00:00+00:00')
        self.assertIsNotNone(third_step,'nested consult must not be mistaken for a repeated revision')
        self.assertEqual(third_step['member_id'],third)
    def test_successor_keeps_completion_contract(self):
        planned=group_actions.next_steps({'id':1,'goal':'完整目标'}, {'id':1,'member_id':10,'input':{}},
            {'kind':'handoff','target_member_id':20,'goal':'写作','completion_criteria':'不少于三项','context_message_ids':[99],'attachment_ids':[]})[0]
        self.assertEqual(planned.get('completion_criteria'),'不少于三项')
    def test_explicit_old_group_message_is_in_execution_context(self):
        task=self.route([self.fx.member_ids[0]])
        step=store.claim_next('test','2026-10-13T00:00:00+00:00')
        with db.tx() as c:
            old=c.execute("INSERT INTO chat_group_messages(group_id,user_id,turn_id,role,content,status,created_at) VALUES (?,?,?,'user','早期重要约束XYZ','completed','now')",(self.fx.group_id,self.fx.user_id,step['turn_id'])).lastrowid
            for _ in range(30): c.execute("INSERT INTO chat_group_messages(group_id,user_id,turn_id,role,content,status,created_at) VALUES (?,?,?,'user','较新资料','completed','now')",(self.fx.group_id,self.fx.user_id,step['turn_id']))
        step['input']['context_message_ids']=[old]
        step['input']['completion_criteria']='不少于三项'
        messages=group_context.build_execution(self.fx.user_id,self.fx.group_id,task,step,remaining_calls=5)
        self.assertIn('早期重要约束XYZ',json.dumps(messages,ensure_ascii=False))

if __name__=='__main__': unittest.main()
