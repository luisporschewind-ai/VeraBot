import unittest
from uuid import uuid4
from group_execution_test_support import GroupExecutionFixture,db
from verabot.db import group_execution_store as s,group_store

class EventRepairTests(unittest.TestCase):
    def setUp(self):self.fx=GroupExecutionFixture()
    def test_replay_has_message_identity_task_updates_and_final_snapshot(self):
        t=s.create_input(self.fx.user_id,self.fx.group_id,{'client_request_id':'r','message':'问题','target_member_ids':[self.fx.member_ids[0]]})
        p=s.claim_next('test','2026-10-13T00:00:00+00:00');s.apply_route(p['id'],p['lease_token'],p['version'],{'intent':'respond','speaker_member_ids':[self.fx.member_ids[0]],'goal':'问题','missing_information':[]})
        a=s.claim_next('test','2026-10-13T00:00:00+00:00');s.save_snapshot(a['id'],a['lease_token'],a['version'],'正在回复')
        cursor=s.input_receipt(self.fx.user_id,self.fx.group_id,'r')['event_cursor']
        frames=s.events(self.fx.user_id,self.fx.group_id,cursor)
        self.assertTrue(all(x.get('group_id')==self.fx.group_id for x in frames),'Swift envelope requires group_id on actual backend frames')
        start=next((x for x in frames if x['kind']=='message_start'),None)
        self.assertIsNotNone(start)
        self.assertEqual(start['payload']['message']['member_id'],self.fx.member_ids[0])
        s.commit_step(a['id'],a['lease_token'],a['version'],{'status':'completed','content':'完整回复','action':{'kind':'completed'}})
        final=s.execution_snapshot(self.fx.user_id,self.fx.group_id)
        self.assertEqual(final['messages'][-1]['content'],'完整回复')
        self.assertEqual(final['messages'][-1]['status'],'completed')
        self.assertTrue(any(x['kind']=='task_updated' and x['payload']['task']['state']=='completed' for x in s.events(self.fx.user_id,self.fx.group_id,cursor)))
    def test_clear_does_not_reuse_event_cursor(self):
        s.create_input(self.fx.user_id,self.fx.group_id,{'client_request_id':'r1','message':'旧问题'})
        old=s.execution_snapshot(self.fx.user_id,self.fx.group_id)['event_cursor']
        group_store.delete_group(self.fx.user_id,self.fx.group_id,clear_only=True)
        s.create_input(self.fx.user_id,self.fx.group_id,{'client_request_id':'r2','message':'新问题'})
        self.assertGreater(s.execution_snapshot(self.fx.user_id,self.fx.group_id)['event_cursor'],old)
    def test_delete_group_does_not_lose_call_identity_or_known_late_usage(self):
        t=s.create_input(self.fx.user_id,self.fx.group_id,{'client_request_id':'r','message':'问题'})
        s.record_call('late',self.fx.user_id,self.fx.group_id,t['id'],None,'group_routing',None,True)
        group_store.delete_group(self.fx.user_id,self.fx.group_id)
        self.assertTrue(s.record_call('late',self.fx.user_id,self.fx.group_id,t['id'],None,'group_routing',{'total_tokens':9},False))
        self.assertFalse(s.record_call('late',self.fx.user_id,self.fx.group_id,t['id'],None,'group_routing',{'total_tokens':9},False))
        with db.tx() as c:self.assertEqual(c.execute('SELECT SUM(total_tokens) FROM usage_log WHERE user_id=?',(self.fx.user_id,)).fetchone()[0],9)

if __name__=='__main__':unittest.main()
