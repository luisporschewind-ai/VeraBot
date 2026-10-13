import unittest,json
import owned_task_store_test as support
from verabot import db
class SafetyTests(unittest.TestCase):
 setUp=support.OwnedTests.setUp
 tearDown=support.OwnedTests.tearDown
 create=support.OwnedTests.create
 def test_cancelled_step_cannot_leave_unbound_approval(self):
  from verabot.db import owned_task_store as s,action_store
  t=self.create()
  with db.tx(immediate=True) as c:step=s.claim_next(c,'w',db.now_iso())
  self.client.post(f"/api/owned-tasks/{t['id']}/stop",json={'expected_version':1})
  with self.assertRaises(ValueError):
   action_store.insert(self.uid,bot_id=self.bid,kind='mcp_tool_call',server_id=None,tool_full_name='x',payload_enc=b'x',payload_hash='x',tool_def_hash='x',expires_at='2999-01-01',owned_step=step)
  with db.tx() as c:self.assertEqual(c.execute('SELECT COUNT(*) FROM pending_actions').fetchone()[0],0)
 def test_daily_unknown_usage_keeps_conservative_reservation(self):
  from verabot.db import owned_task_store as s
  t=self.create()
  with db.tx(immediate=True) as c:
   step=s.claim_next(c,'w',db.now_iso());cid=s.begin_call(c,step);s.record_call(c,cid,None,1)
   self.assertGreater(s.get(c,self.uid,t['id'])['reserved_tokens'],0)
 def test_scheduler_cancel_fences_running_owned_step(self):
  # The store must recheck scheduled run cancellation at actual execution, not only next scan.
  from verabot.db import owned_task_store as s,scheduled_run_store as runs,scheduled_task_store as tasks
  t=self.create()
  with db.tx(immediate=True) as c:
   sid=tasks.insert(c,dict(user_id=self.uid,bot_id=self.bid,title='t',instruction='i',state='active',timezone='UTC',start_at_utc=db.now_iso(),repeat='once',created_at=db.now_iso(),updated_at=db.now_iso()))
   from datetime import datetime,timezone
   rid=runs.insert(c,tasks.fetch(c,self.uid,sid),datetime.now(timezone.utc),datetime.now(timezone.utc))
   s.link_schedule(c,t['id'],rid);step=s.claim_next(c,'w',db.now_iso())
   runs.cancel_pending(c,sid,datetime.now(timezone.utc),include_running=True)
   self.assertIsNone(s.live(c,step))
 def test_unknown_operation_survives_version_change(self):
  from verabot.db import owned_task_store as store
  t=self.create()
  with db.tx() as c:
   c.execute("INSERT INTO pending_actions(user_id,bot_id,kind,payload_enc,payload_hash,status,result,created_at,expires_at,tool_full_name,owned_task_id,owned_task_version) VALUES (?,?,'mcp_tool_call',X'00','same','unknown','Timed out',?,'2999-01-01','tool',?,1)",(self.uid,self.bid,db.now_iso(),t['id']))
   self.assertIsNotNone(store.previous_action(c,t['id'],2,'tool','same'))
 def test_consult_never_recalls_private_history_or_original_goal(self):
  from unittest.mock import patch
  from verabot.services.owned_tasks.context import build
  from verabot.db import owned_task_store as store
  t=self.create()
  with db.tx() as c:task=store.get(c,self.uid,t['id'])
  bot=db.get_bot(self.uid,self.bid)
  with patch('verabot.services.memory.recall',side_effect=AssertionError('implicit recall')):
   messages=build(task,{'input_json':'{"question":"public question"}','kind':'consult'},bot)
  self.assertNotIn('Write a report',messages[-1]['content'])
 def test_consult_requires_ask_bot_not_only_delegate_list(self):
  from verabot.db import owned_task_store as store
  with db.tx() as c:
   target=c.execute("INSERT INTO bots(user_id,name,accept_delegation,created_at) VALUES (?,'C',1,'now')",(self.uid,)).lastrowid
   c.execute('UPDATE bots SET delegate_to=? WHERE id=?',(json.dumps([target]),self.bid))
  t=self.create()
  with db.tx(immediate=True) as c:
   step=store.claim_next(c,'w',db.now_iso())
   with self.assertRaises(ValueError):store.commit_step(c,step,{'action':'consult','bot_id':target,'text':'q'})
 def test_confirm_fences_revoked_frozen_tool_at_claim(self):
  from verabot.db import owned_task_store as store,action_store
  t=self.create()
  with db.tx(immediate=True) as c:
   c.execute('UPDATE bots SET allowed_tools=? WHERE id=?',(json.dumps(['tool']),self.bid))
   store.update_task(c,t['id'],{'authorization_json':'{"tool":"hash"}'})
   step=store.claim_next(c,'w',db.now_iso())
   aid=c.execute("INSERT INTO pending_actions(user_id,bot_id,kind,payload_enc,payload_hash,tool_def_hash,tool_full_name,status,created_at,expires_at) VALUES (?,?,'mcp_tool_call',X'00','x','hash','tool','pending',?,'2999-01-01')",(self.uid,self.bid,db.now_iso())).lastrowid
   store.bind_action(c,step,aid);store.commit_step(c,step,{'action':'await_approval','text':'Approve','action_id':aid})
   c.execute("UPDATE bots SET allowed_tools='[]' WHERE id=?",(self.bid,))
  self.assertNotEqual(action_store.claim_for_execution(self.uid,aid)[0],'claimed')
 def test_initial_active_write_definition_is_freezable_but_change_is_not(self):
  from unittest.mock import patch
  from verabot.services.owned_tasks import policy
  bot=db.get_bot(self.uid,self.bid);bot['allowed_tools']=['mcp__fixture__write']
  tool=dict(full_name='mcp__fixture__write',mcp_name='write',risk='write',status='active',accepted_hash=None,def_hash='hash')
  with patch('verabot.services.owned_tasks.policy.mcp.connected_tool_rows',return_value=[(tool,{'id':1})]):
   self.assertIn(tool['full_name'],policy.snapshot(self.uid,bot))
   tool['status']='changed';self.assertNotIn(tool['full_name'],policy.snapshot(self.uid,bot))
if __name__=='__main__':unittest.main()
