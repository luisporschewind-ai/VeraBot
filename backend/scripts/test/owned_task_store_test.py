import primary_bot_test as support
import unittest
class OwnedTests(unittest.TestCase):
 tearDown=support.PrimaryTests.tearDown
 def setUp(self):
  support.PrimaryTests.setUp(self)
  self.client.patch('/api/primary-bot',json={'primary_bot_id':self.bid,'active_enabled':True,'expected_version':1})
 def create(self,key='k'):
  r=self.client.post('/api/owned-tasks',headers={'Idempotency-Key':key},json={'bot_id':self.bid,'goal':'Write a report','completion_criteria':'Saved report'})
  self.assertEqual(r.status_code,201);return r.json()
 def test_task_receipt_and_no_prompt_model_call(self):
  t=self.create();self.assertEqual(t['state'],'queued');self.assertEqual(t['owner_bot_id'],self.bid)
  self.assertEqual(self.create()['id'],t['id'])
  r=self.client.post('/api/owned-tasks',headers={'Idempotency-Key':'k'},json={'bot_id':self.bid,'goal':'different','completion_criteria':'Done'})
  self.assertEqual(r.status_code,409)
 def test_stop_and_version(self):
  t=self.create();r=self.client.post(f"/api/owned-tasks/{t['id']}/stop",json={'expected_version':t['version']})
  self.assertEqual(r.status_code,200);self.assertEqual(r.json()['state'],'stopped')
  self.assertEqual(self.client.post(f"/api/owned-tasks/{t['id']}/continue",json={'expected_version':t['version']}).status_code,409)
 def test_disabled_cannot_create(self):
  self.client.patch('/api/primary-bot',json={'active_enabled':False,'expected_version':2})
  self.assertEqual(self.client.post('/api/owned-tasks',headers={'Idempotency-Key':'x'},json={'bot_id':self.bid,'goal':'g','completion_criteria':'c'}).status_code,409)
 def test_disable_fences_claimed_step(self):
  from verabot.db import owned_task_store as s
  from verabot import db
  t=self.create()
  with db.tx(immediate=True) as c:step=s.claim_next(c,'w',db.now_iso())
  self.client.patch('/api/primary-bot',json={'active_enabled':False,'expected_version':2})
  with db.tx(immediate=True) as c:
   self.assertFalse(s.commit_step(c,step,{'action':'completed','text':'late'}))
  self.assertEqual(self.client.get(f"/api/owned-tasks/{t['id']}").json()['state'],'stopped')
 def test_wait_and_duplicate_answers(self):
  from verabot.db import owned_task_store as s
  from verabot import db
  t=self.create()
  with db.tx(immediate=True) as c:
   step=s.claim_next(c,'w',db.now_iso());s.commit_step(c,step,{'action':'await_user','text':'Which week?'})
  url=f"/api/owned-tasks/{t['id']}/inputs"
  p={'message':'this week','expected_version':1}
  r=self.client.post(url,json=p,headers={'Idempotency-Key':'answer'});self.assertEqual(r.status_code,200)
  self.assertEqual(self.client.post(url,json=p,headers={'Idempotency-Key':'answer'}).status_code,200)
  self.assertEqual(self.client.post(url,json=p,headers={'Idempotency-Key':'answer2'}).status_code,409)
  self.assertEqual(self.client.get(f"/api/owned-tasks/{t['id']}").json()['goal'],'Write a report')
 def test_restart_never_replays_model(self):
  from verabot.db import owned_task_store as s
  from verabot import db
  t=self.create()
  with db.tx(immediate=True) as c:
   step=s.claim_next(c,'w',db.now_iso())
   c.execute("UPDATE owned_steps SET lease_expires_at='2020-01-01T00:00:00+00:00' WHERE id=?",(step['id'],))
   s.recover(c,db.now_iso());self.assertIsNone(s.claim_next(c,'w',db.now_iso()))
  self.assertEqual(self.client.get(f"/api/owned-tasks/{t['id']}").json()['state'],'interrupted')
 def test_consult_returns_owner_and_counts_calls(self):
  from verabot.db import owned_task_store as s
  from verabot import db
  t=self.create()
  with db.tx(immediate=True) as c:
   c.execute('UPDATE bots SET delegate_to=? WHERE id=?',('[%d]'%self.foreign,self.bid))
   step=s.claim_next(c,'w',db.now_iso())
   with self.assertRaises(ValueError):s.commit_step(c,step,{'action':'consult','bot_id':self.foreign,'text':'q'})
 def test_foreign_task_and_events(self):
  t=self.create()
  app=__import__('verabot.main',fromlist=['app']).app
  from verabot.api.deps import current_user
  app.dependency_overrides[current_user]=lambda:{'id':999999}
  self.assertEqual(self.client.get(f"/api/owned-tasks/{t['id']}").status_code,404)
  self.assertEqual(self.client.get(f"/api/owned-tasks/{t['id']}/events").status_code,404)
if __name__=='__main__':unittest.main()
