import asyncio
import importlib
from datetime import timedelta
from unittest.mock import patch
from concurrent.futures import ThreadPoolExecutor
from scheduled_task_test_support import DBTest, db, NOW
from verabot.services.scheduled_tasks import service, clock
from verabot.services.scheduled_tasks.contracts import ExecutionResult
from verabot.db import scheduled_run_store as runs

class WorkerTests(DBTest):
    def job(self, paused=False):
        with patch.object(clock,'now',return_value=NOW):
            t=service.create(1,self.payload(),'key')
            if paused: service.transition(1,t['id'],'pause',t['version'])
            return service.run_now(1,t['id'],'manual')
    def test_claim_competition_and_expiry(self):
        self.job()
        def claim(owner):
            with db.tx(immediate=True) as c: return runs.claim_next(c,owner,NOW)
        with ThreadPoolExecutor(2) as pool:
            claimed=list(pool.map(claim,['a','b']))
        self.assertEqual(sum(x is not None for x in claimed),1)
        job=next(x for x in claimed if x)
        with db.tx(immediate=True) as c:
            self.assertFalse(runs.finish(c,job['id'],'wrong',ExecutionResult(),NOW))
            self.assertTrue(runs.renew(c,job['id'],job['lease_token'],NOW+timedelta(seconds=15)))
            self.assertFalse(runs.finish(c,job['id'],job['lease_token'],ExecutionResult(),NOW+timedelta(seconds=106)))
        worker=importlib.import_module('verabot.services.scheduled_tasks.worker')
        self.assertEqual(worker.recover_expired(NOW+timedelta(seconds=50)),0)
        self.assertEqual(worker.recover_expired(NOW+timedelta(seconds=106)),1)
        with db.tx() as c:
            self.assertEqual(runs.get(c,job['id'])['state'],'interrupted')
            self.assertEqual(runs.attempts(c,job['id'])[0]['usage_unknown'],1)
            self.assertIsNone(runs.claim_next(c,'new',NOW+timedelta(seconds=107)))
    def test_retry_limit_and_paused_manual(self):
        job=self.job(paused=True)
        worker=importlib.import_module('verabot.services.scheduled_tasks.worker')
        executor=importlib.import_module('verabot.services.scheduled_tasks.executor')
        async def failure(run):
            return ExecutionResult(state='failed',error_code='provider_temporary',error_summary='稍后重试',usage={'total_tokens':5})
        for offset in (0,30,150):
            with patch.object(clock,'now',return_value=NOW+timedelta(seconds=offset)),patch.object(executor,'run_scheduled',failure):
                self.assertTrue(asyncio.run(worker.process_one('worker')))
            with db.tx() as c:
                r=runs.get(c,job['id'])
                if offset<150: self.assertEqual(r['state'],'retry_wait')
                else: self.assertEqual(r['state'],'failed')
        with db.tx() as c:
            self.assertEqual(len(runs.attempts(c,job['id'])),3)
            self.assertEqual(c.execute('SELECT SUM(total_tokens) FROM usage_log').fetchone()[0],15)
            self.assertEqual(c.execute('SELECT state FROM scheduled_tasks').fetchone()[0],'paused')
    def test_pause_cancels_pending(self):
        job=self.job()
        with patch.object(clock,'now',return_value=NOW):
            service.transition(1,job['task_id'],'pause',1)
        with db.tx() as c: self.assertEqual(runs.get(c,job['id'])['state'],'cancelled')
    def test_running_pause_cancels_and_preserves_known_usage(self):
        job=self.job()
        worker=importlib.import_module('verabot.services.scheduled_tasks.worker')
        executor=importlib.import_module('verabot.services.scheduled_tasks.executor')
        async def scenario():
            entered=asyncio.Event()
            async def slow(run):
                with db.tx(immediate=True) as c:
                    runs.record_usage(c,run['id'],run['lease_token'],{'total_tokens':4},NOW)
                entered.set()
                await asyncio.Event().wait()
            with patch.object(clock,'now',return_value=NOW),patch.object(executor,'run_scheduled',slow):
                work=asyncio.create_task(worker.process_one('worker'))
                await asyncio.wait_for(entered.wait(),2)
                service.transition(1,job['task_id'],'pause',1)
                await asyncio.wait_for(work,4)
        asyncio.run(scenario())
        with db.tx() as c:
            self.assertEqual(runs.get(c,job['id'])['state'],'cancelled')
            self.assertEqual(runs.attempts(c,job['id'])[0]['usage_json'],'{"total_tokens": 4}')
            self.assertEqual(c.execute('SELECT COUNT(*) FROM messages').fetchone()[0],0)
    def test_expired_cancelled_run_stays_cancelled_without_notification(self):
        for action in ('pause','delete'):
            self.setUp()
            job=self.job()
            with db.tx(immediate=True) as c:
                run=runs.claim_next(c,'worker',NOW)
                runs.record_usage(c,run['id'],run['lease_token'],{'total_tokens':3},NOW)
            with patch.object(clock,'now',return_value=NOW):
                service.transition(1,job['task_id'],action,1)
            worker=importlib.import_module('verabot.services.scheduled_tasks.worker')
            worker.recover_expired(NOW+timedelta(seconds=91))
            with db.tx() as c:
                self.assertEqual(runs.get(c,job['id'])['state'],'cancelled')
                self.assertEqual(runs.attempts(c,job['id'])[0]['usage_unknown'],1)
                self.assertEqual(c.execute('SELECT COUNT(*) FROM notifications').fetchone()[0],0)
                self.assertEqual(c.execute('SELECT SUM(total_tokens) FROM usage_log').fetchone()[0],3)
