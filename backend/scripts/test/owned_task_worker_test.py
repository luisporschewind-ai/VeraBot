import unittest, asyncio, json
from unittest.mock import patch
import owned_task_store_test as support
from verabot import db
class WorkerTests(unittest.TestCase):
 setUp=support.OwnedTests.setUp
 tearDown=support.OwnedTests.tearDown
 create=support.OwnedTests.create
 def run_step(self):
  from verabot.services.owned_tasks import worker
  return asyncio.run(worker.process_one('test'))
 def test_complete_and_no_idle_calls(self):
  t=self.create()
  async def fake(*args,**kw):return {'content':json.dumps({'action':'completed','text':'The report is saved.'})},{'prompt_tokens':3,'completion_tokens':4,'total_tokens':7}
  with patch('verabot.services.llm.complete',fake):self.assertTrue(self.run_step());self.assertFalse(self.run_step())
  data=self.client.get(f"/api/owned-tasks/{t['id']}").json();self.assertEqual(data['state'],'completed');self.assertEqual(data['used_tokens'],7)
  with db.tx() as c:self.assertEqual(c.execute('SELECT COUNT(*) FROM messages WHERE source_kind=\'owned_task\'').fetchone()[0],1)
 def test_wait_two_answers_preserve_goal_and_progress(self):
  t=self.create();actions=iter([{'action':'await_user','text':'Which week?'},{'action':'await_user','text':'Which product?'},{'action':'completed','text':'Done'}])
  async def fake(*args,**kw):return {'content':json.dumps(next(actions))},{'prompt_tokens':3,'completion_tokens':4,'total_tokens':7}
  with patch('verabot.services.llm.complete',fake):
   for n in range(2):
    self.run_step();data=self.client.get(f"/api/owned-tasks/{t['id']}").json()
    r=self.client.post(f"/api/owned-tasks/{t['id']}/inputs",json={'message':'answer'+str(n),'expected_version':data['version']},headers={'Idempotency-Key':'a'+str(n)})
    self.assertEqual(r.status_code,200)
   self.run_step()
  self.assertEqual(self.client.get(f"/api/owned-tasks/{t['id']}").json()['goal'],'Write a report')
 def test_consult_returns_owner(self):
  with db.tx() as c:
   target=c.execute("INSERT INTO bots(user_id,name,accept_delegation,created_at) VALUES (?,'C',1,'now')",(self.uid,)).lastrowid
   c.execute('UPDATE bots SET delegate_to=?,allowed_tools=? WHERE id=?',(json.dumps([target]),json.dumps(['ask_bot']),self.bid))
  t=self.create();actions=iter([{'action':'consult','bot_id':target,'text':'Analyze the report'},{'action':'completed','text':'Analysis'},{'action':'completed','text':'Final report'}])
  async def fake(*args,**kw):return {'content':json.dumps(next(actions))},{'prompt_tokens':3,'completion_tokens':4,'total_tokens':7}
  with patch('verabot.services.llm.complete',fake):
   for _ in range(3):self.run_step()
  data=self.client.get(f"/api/owned-tasks/{t['id']}").json();self.assertEqual(data['state'],'completed');self.assertEqual(data['chain_calls'],3)
 def test_cancel_late_result_keeps_usage(self):
  t=self.create()
  async def fake(*args,**kw):
   self.client.post(f"/api/owned-tasks/{t['id']}/stop",json={'expected_version':1})
   return {'content':'{"action":"completed","text":"late"}'},{'prompt_tokens':3,'completion_tokens':4,'total_tokens':7}
  with patch('verabot.services.llm.complete',fake):self.run_step()
  data=self.client.get(f"/api/owned-tasks/{t['id']}").json();self.assertEqual(data['state'],'stopped');self.assertEqual(data['used_tokens'],7)
 def test_unknown_usage_is_not_zero(self):
  t=self.create()
  async def fake(*args,**kw):return {'content':'{"action":"completed","text":"result"}'},{}
  with patch('verabot.services.llm.complete',fake):self.run_step()
  with db.tx() as c:self.assertEqual(c.execute('SELECT usage_unknown FROM owned_calls').fetchone()[0],1)
 def test_policy_writes_and_permission_revocation(self):
  from verabot.services.owned_tasks import policy
  bot=db.get_bot(self.uid,self.bid)
  self.assertNotIn('remember',policy.snapshot(self.uid,bot))
  self.assertEqual(policy.allowed(self.uid,bot,{'create_reminder':'builtin'}),[])
 def test_provider_exceeding_output_ceiling_cannot_complete(self):
  t=self.create()
  async def fake(*args,**kw):return {'content':'{"action":"completed","text":"report"}'},{'prompt_tokens':1,'completion_tokens':2049,'total_tokens':2050}
  with patch('verabot.services.llm.complete',fake):self.run_step()
  self.assertEqual(self.client.get(f"/api/owned-tasks/{t['id']}").json()['state'],'awaiting_user')
if __name__=='__main__':unittest.main()
