from unittest.mock import patch
from fastapi.testclient import TestClient
from scheduled_task_test_support import DBTest, NOW, db
from verabot.main import app
from verabot.api.deps import current_user

class APITests(DBTest):
    def setUp(self):
        super().setUp()
        self.time = patch('verabot.services.scheduled_tasks.clock.now', return_value=NOW)
        # Use current time at API boundary to avoid production credentials or auth calls.
        self.time.start()
        self.addCleanup(self.time.stop)
        app.dependency_overrides[current_user] = lambda: {'id':1}
        self.addCleanup(app.dependency_overrides.clear)
        self.client = TestClient(app)
    def create(self, key='create-1'):
        return self.client.post('/api/scheduled-tasks', json=self.payload(), headers={'Idempotency-Key':key})
    def test_create_idempotency_isolation_and_version(self):
        r = self.create()
        self.assertEqual(r.status_code,201,r.text)
        task=r.json()
        self.assertEqual(self.create().json()['id'],task['id'])
        changed=self.payload(); changed['instruction']='another'
        self.assertEqual(self.client.post('/api/scheduled-tasks',json=changed,headers={'Idempotency-Key':'create-1'}).status_code,409)
        path=f"/api/scheduled-tasks/{task['id']}"
        self.assertEqual(self.client.patch(path,json={'expected_version':2,'title':'x'}).status_code,409)
        r=self.client.post(path+'/pause',json={'expected_version':1})
        self.assertEqual(r.status_code,200,r.text)
        self.assertEqual(self.client.post(path+'/run',headers={'Idempotency-Key':'manual-1'}).status_code,202)
        self.assertEqual(self.client.post(path+'/run',headers={'Idempotency-Key':'manual-1'}).status_code,202)
        self.assertEqual(self.client.post(path+'/run',headers={'Idempotency-Key':'manual-2'}).status_code,409)
        app.dependency_overrides[current_user]=lambda:{'id':2}
        for endpoint in (path,path+'/runs',path+'/runs/1'):
            self.assertEqual(self.client.get(endpoint).status_code,404)
    def test_bad_inputs(self):
        for change in ({'timezone':'invalid'}, {'start_at':'2026-10-11T10:00:00'}, {'repeat':'hourly'}, {'instruction':''}, {'bot_id':2}, {'start_at':'2000-01-01T09:00:00+08:00'}):
            p=self.payload(); p.update(change)
            self.assertIn(self.client.post('/api/scheduled-tasks',json=p,headers={'Idempotency-Key':'bad'}).status_code,(400,404,422))
        self.assertEqual(self.create().status_code,201)
        self.assertEqual(self.client.get('/api/scheduled-tasks?limit=101').status_code,422)
    def test_edit_schedule_after_first_run_and_invalid_timezone(self):
        t=self.create().json(); path=f"/api/scheduled-tasks/{t['id']}"
        with patch('verabot.services.scheduled_tasks.clock.now',return_value=NOW.replace(day=12)):
            r=self.client.patch(path,json={'expected_version':1,'repeat':'weekdays'})
            self.assertEqual(r.status_code,200,r.text)
            self.assertGreater(r.json()['next_run_at_utc'],'2026-10-12T01:00:00')
            r=self.client.patch(path,json={'expected_version':2,'timezone':'bad-zone'})
            self.assertEqual(r.status_code,400,r.text)
    def test_edit_cancels_old_queued_and_soft_delete_keeps_history(self):
        t=self.create().json(); path=f"/api/scheduled-tasks/{t['id']}"
        r=self.client.post(path+'/run',headers={'Idempotency-Key':'edit-manual'})
        rid=r.json()['id']
        self.assertEqual(self.client.patch(path,json={'expected_version':1,'instruction':'新内容'}).status_code,200)
        self.assertEqual(self.client.get(path+f'/runs/{rid}').json()['state'],'cancelled')
        self.assertEqual(self.client.request('DELETE',path,json={'expected_version':2}).status_code,200)
        self.assertEqual(self.client.get(path).status_code,404)
        self.assertEqual(self.client.get(path+'/runs').status_code,200)
        self.assertEqual(self.client.post(path+'/run',headers={'Idempotency-Key':'after-delete'}).status_code,404)
    def test_exhausted_once_edit_returns_error(self):
        payload=self.payload(); payload['repeat']='once'
        r=self.client.post('/api/scheduled-tasks',json=payload,headers={'Idempotency-Key':'once'})
        task=r.json()
        with patch('verabot.services.scheduled_tasks.clock.now',return_value=NOW.replace(day=12)):
            r=self.client.patch(f"/api/scheduled-tasks/{task['id']}",json={'expected_version':1,'timezone':'Asia/Shanghai'})
            self.assertEqual(r.status_code,400,r.text)
    def test_completed_schedule_edit_reactivates_but_paused_stays_paused(self):
        from verabot.services.scheduled_tasks import scheduler,worker,executor,clock
        from verabot.services.scheduled_tasks.contracts import ExecutionResult
        import asyncio
        p=self.payload(); p['repeat']='once'
        task=self.client.post('/api/scheduled-tasks',json=p,headers={'Idempotency-Key':'once'}).json()
        due=NOW.replace(minute=1)
        async def result(run): return ExecutionResult(text='完成')
        with patch.object(clock,'now',return_value=due),patch.object(executor,'run_scheduled',result):
            scheduler.tick(due); asyncio.run(worker.process_one('worker'))
        path=f"/api/scheduled-tasks/{task['id']}"
        self.assertEqual(self.client.get(path).json()['state'],'completed')
        r=self.client.patch(path,json={'expected_version':1,'start_at':'2026-10-12T09:00:00+08:00'})
        self.assertEqual(r.status_code,200,r.text)
        self.assertEqual(r.json()['state'],'active')
        self.client.post(path+'/pause',json={'expected_version':2})
        r=self.client.patch(path,json={'expected_version':3,'start_at':'2026-10-13T09:00:00+08:00'})
        self.assertEqual(r.json()['state'],'paused')

if __name__ == '__main__':
    import unittest
    unittest.main()
