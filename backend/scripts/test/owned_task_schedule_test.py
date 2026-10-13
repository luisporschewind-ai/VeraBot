import json,unittest
import owned_task_store_test as support
from datetime import datetime,timezone,timedelta
from verabot import db
class ScheduleTests(unittest.TestCase):
 setUp=support.OwnedTests.setUp
 tearDown=support.OwnedTests.tearDown
 def test_owned_occurrence_and_wait_skips_duplicate(self):
  when=datetime.now(timezone.utc)+timedelta(minutes=2)
  r=self.client.post('/api/scheduled-tasks',headers={'Idempotency-Key':'sched'},json={'bot_id':self.bid,'title':'Report','instruction':'Write report','start_at':when.isoformat(),'timezone':'UTC','repeat':'daily','execution_mode':'owned'})
  self.assertEqual(r.status_code,201)
  from verabot.services.scheduled_tasks import scheduler
  scheduler.tick(when);scheduler.tick(when)
  with db.tx() as c:self.assertEqual(c.execute('SELECT COUNT(*) FROM owned_tasks').fetchone()[0],1)
  scheduler.tick(when+timedelta(days=1))
  with db.tx() as c:self.assertEqual(c.execute('SELECT COUNT(*) FROM owned_tasks').fetchone()[0],1)
 def test_owned_manual_does_not_run_v1_executor(self):
  when=datetime.now(timezone.utc)+timedelta(minutes=2)
  r=self.client.post('/api/scheduled-tasks',headers={'Idempotency-Key':'manual-sched'},json={'bot_id':self.bid,'title':'Report','instruction':'Write report','start_at':when.isoformat(),'timezone':'UTC','execution_mode':'owned'})
  self.assertEqual(r.status_code,201)
  r=self.client.post(f"/api/scheduled-tasks/{r.json()['id']}/run",headers={'Idempotency-Key':'run'})
  self.assertEqual(r.status_code,202)
  with db.tx() as c:self.assertEqual(c.execute('SELECT COUNT(*) FROM owned_tasks').fetchone()[0],1)
 def test_interrupted_scheduled_task_can_resume_same_instance(self):
  from verabot.db import owned_task_store as store
  when=datetime.now(timezone.utc)+timedelta(minutes=2)
  created=self.client.post('/api/scheduled-tasks',headers={'Idempotency-Key':'resume-sched'},json={'bot_id':self.bid,'title':'Report','instruction':'Write report','start_at':when.isoformat(),'timezone':'UTC','execution_mode':'owned'})
  self.assertEqual(created.status_code,201)
  sid=created.json()['id'];self.client.post(f"/api/scheduled-tasks/{sid}/run",headers={'Idempotency-Key':'start'})
  with db.tx(immediate=True) as c:
   task=store.list_tasks(c,self.uid)[0]
   step=store.claim_next(c,'w',db.now_iso())
   store.commit_step(c,step,{'action':'interrupted','text':'Need verification','blocker_code':'execution_unknown'})
   store.finish_schedules(c)
  r=self.client.post(f"/api/owned-tasks/{task['id']}/continue",json={'expected_version':1})
  self.assertEqual(r.status_code,200)
  with db.tx(immediate=True) as c:
   next_step=store.claim_next(c,'w',db.now_iso());self.assertIsNotNone(store.live(c,next_step))
if __name__=='__main__':unittest.main()
