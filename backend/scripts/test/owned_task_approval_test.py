import unittest
import owned_task_store_test as support
from verabot import db
class ApprovalTests(unittest.TestCase):
 setUp=support.OwnedTests.setUp
 tearDown=support.OwnedTests.tearDown
 create=support.OwnedTests.create
 def test_approval_binding_stopped_version_is_not_executable(self):
  from verabot.db import owned_task_store as s
  from verabot.services.owned_tasks import approvals
  t=self.create()
  with db.tx(immediate=True) as c:
   step=s.claim_next(c,'w',db.now_iso())
   # A local action fixture bypasses encryption only to test task-fencing, no remote invocation.
   aid=c.execute("INSERT INTO pending_actions(user_id,bot_id,kind,payload_enc,payload_hash,status,created_at,expires_at) VALUES (?,?,'mcp',X'00','x','pending',?,'2999-01-01')",(self.uid,self.bid,db.now_iso())).lastrowid
   c.execute('UPDATE bots SET allowed_tools=? WHERE id=?',('["tool"]',self.bid));s.update_task(c,t['id'],{'authorization_json':'{"tool":"hash"}'});c.execute("UPDATE pending_actions SET tool_full_name='tool',tool_def_hash='hash' WHERE id=?",(aid,));s.bind_action(c,step,aid)
   s.commit_step(c,step,{'action':'await_approval','text':'Approve','action_id':aid})
  approvals.preflight(self.uid,aid)
  self.client.post(f"/api/owned-tasks/{t['id']}/stop",json={'expected_version':1})
  with self.assertRaises(ValueError):approvals.preflight(self.uid,aid)
 def test_approval_success_creates_one_successor(self):
  from verabot.db import owned_task_store as s
  from verabot.services.owned_tasks import approvals
  t=self.create()
  with db.tx(immediate=True) as c:
   step=s.claim_next(c,'w',db.now_iso());aid=c.execute("INSERT INTO pending_actions(user_id,bot_id,kind,payload_enc,payload_hash,status,created_at,expires_at) VALUES (?,?,'mcp',X'00','x','pending',?,'2999-01-01')",(self.uid,self.bid,db.now_iso())).lastrowid
   c.execute('UPDATE bots SET allowed_tools=? WHERE id=?',('["tool"]',self.bid));s.update_task(c,t['id'],{'authorization_json':'{"tool":"hash"}'});c.execute("UPDATE pending_actions SET tool_full_name='tool',tool_def_hash='hash' WHERE id=?",(aid,));s.bind_action(c,step,aid);s.commit_step(c,step,{'action':'await_approval','text':'Approve','action_id':aid})
   c.execute("UPDATE pending_actions SET status='done',result='Executed' WHERE id=?",(aid,))
  approvals.resolve(self.uid,aid);approvals.resolve(self.uid,aid)
  data=self.client.get(f"/api/owned-tasks/{t['id']}").json();self.assertEqual(data['state'],'queued');self.assertEqual(len(data['steps']),2)
 def test_real_tool_result_checkpoint_enters_successor(self):
  from verabot.db import owned_task_store as s
  from verabot.services.owned_tasks import approvals
  from verabot.services.actions import _encrypt
  t=self.create()
  with db.tx(immediate=True) as c:
   c.execute('UPDATE bots SET allowed_tools=? WHERE id=?',('["tool"]',self.bid));s.update_task(c,t['id'],{'authorization_json':'{"tool":"hash"}'})
   step=s.claim_next(c,'w',db.now_iso())
   aid=c.execute("INSERT INTO pending_actions(user_id,bot_id,kind,payload_enc,payload_hash,tool_full_name,tool_def_hash,status,result,created_at,expires_at) VALUES (?,?,'mcp_tool_call',X'00','x','tool','hash','pending','summary',?,'2999-01-01')",(self.uid,self.bid,db.now_iso())).lastrowid
   s.bind_action(c,step,aid);s.commit_step(c,step,{'action':'await_approval','text':'Approve','action_id':aid})
   s.checkpoint_action(c,self.uid,aid,_encrypt({'content':'resource-123'}))
   c.execute("UPDATE pending_actions SET status='done' WHERE id=?",(aid,))
  approvals.resolve(self.uid,aid)
  with db.tx() as c:
   last=s.steps(c,t['id'])[-1]
   self.assertIn('resource-123',last['input_json'])
 def test_confirmation_api_executes_once_and_passes_real_result(self):
  from unittest.mock import patch
  from verabot.db import owned_task_store as s,mcp_store
  from verabot.services import actions
  from verabot.tools.registry import ToolContext
  from verabot.services.owned_tasks import worker
  import asyncio,json
  server=mcp_store.insert_server(self.uid,dict(slug='fixture',catalog_id='fixture',name='Fixture',transport='http',url='http://127.0.0.1:1',trust='test',auth='none'),'connected')
  name='mcp__fixture__write'
  mcp_store.upsert_tool(self.uid,server['id'],dict(full_name=name,mcp_name='write',description='fixture write',input_schema={'type':'object'},def_hash='hash',risk='write'))
  with db.tx() as c:c.execute('UPDATE bots SET allowed_tools=? WHERE id=?',(json.dumps([name]),self.bid))
  t=self.create()
  with db.tx(immediate=True) as c:
   s.update_task(c,t['id'],{'authorization_json':json.dumps({name:'hash'})});step=s.claim_next(c,'w',db.now_iso())
  ctx=ToolContext(user_id=self.uid,bot=db.get_bot(self.uid,self.bid));ctx.owned_step=step
  tool=mcp_store.get_tool_by_full_name(self.uid,name)
  pending=actions.create_mcp_pending(ctx,server,tool,{'title':'report'})
  with db.tx(immediate=True) as c:s.commit_step(c,step,{'action':'await_approval','text':'Approve','action_id':pending['action_id']})
  invocations=[]
  def invoke(*args,**kwargs):invocations.append(args);return {'code':'ok','content':'resource-id-123'}
  with patch('verabot.services.actions.mcp.invoke',invoke):
   first=self.client.post(f"/api/pending-actions/{pending['action_id']}/confirm")
   self.assertEqual(first.status_code,200,first.text)
   self.assertEqual(self.client.post(f"/api/pending-actions/{pending['action_id']}/confirm").status_code,409)
  self.assertEqual(len(invocations),1)
  with db.tx() as c:self.assertIn('resource-id-123',s.steps(c,t['id'])[-1]['input_json'])
  async def provider(messages,*args,**kwargs):
   self.assertIn('resource-id-123',messages[-1]['content'])
   return {'content':'{"action":"completed","text":"Final saved report"}'},{'prompt_tokens':2,'completion_tokens':3,'total_tokens':5}
  with patch('verabot.services.llm.complete',provider):asyncio.run(worker.process_one('w'))
  self.assertEqual(self.client.get(f"/api/owned-tasks/{t['id']}").json()['state'],'completed')
 def test_crashed_confirmation_becomes_user_help_without_replay(self):
  from verabot.db import owned_task_store as s
  from verabot.services.owned_tasks import approvals
  t=self.create()
  with db.tx(immediate=True) as c:
   step=s.claim_next(c,'w',db.now_iso())
   aid=c.execute("INSERT INTO pending_actions(user_id,bot_id,kind,payload_enc,payload_hash,status,result,created_at,decided_at,expires_at) VALUES (?,?,'mcp_tool_call',X'00','x','done','执行中…',?,'2000-01-01T00:00:00+00:00','2999-01-01')",(self.uid,self.bid,db.now_iso())).lastrowid
   s.bind_action(c,step,aid);s.commit_step(c,step,{'action':'await_approval','text':'Approve','action_id':aid})
  approvals.reconcile()
  self.assertEqual(self.client.get(f"/api/owned-tasks/{t['id']}").json()['state'],'awaiting_user')
if __name__=='__main__':unittest.main()
