from datetime import timedelta
import importlib
from unittest.mock import patch
from scheduled_task_test_support import DBTest, db, NOW
from verabot.services.scheduled_tasks import clock, service
from verabot.services.scheduled_tasks.contracts import ExecutionResult
from verabot.db import scheduled_run_store as runs

class DeliveryTests(DBTest):
    def job(self):
        with patch.object(clock,'now',return_value=NOW):
            t=service.create(1,self.payload(),'key')
            service.run_now(1,t['id'],'manual')
            with db.tx(immediate=True) as c: return runs.claim_next(c,'worker',NOW)
    def test_atomic_dedupe_and_deleted_message_not_restored(self):
        job=self.job()
        delivery=importlib.import_module('verabot.services.scheduled_tasks.delivery')
        with patch.object(clock,'now',return_value=NOW):
            self.assertTrue(delivery.commit_result(job['id'],job['lease_token'],ExecutionResult(text='结果')))
            self.assertFalse(delivery.commit_result(job['id'],job['lease_token'],ExecutionResult(text='第二次')))
        with db.tx() as c:
            self.assertEqual(c.execute('SELECT COUNT(*) FROM messages').fetchone()[0],1)
            self.assertEqual(c.execute('SELECT COUNT(*) FROM notifications').fetchone()[0],1)
            c.execute('DELETE FROM messages')
        with patch.object(clock,'now',return_value=NOW):
            self.assertFalse(delivery.commit_result(job['id'],job['lease_token'],ExecutionResult(text='结果')))
        with db.tx() as c:
            self.assertEqual(c.execute('SELECT COUNT(*) FROM messages').fetchone()[0],0)
            self.assertEqual(runs.get(c,job['id'])['result_text'],'结果')
    def test_cancel_prevents_result(self):
        job=self.job()
        delivery=importlib.import_module('verabot.services.scheduled_tasks.delivery')
        with patch.object(clock,'now',return_value=NOW):
            service.transition(1,job['task_id'],'pause',1)
            delivery.commit_result(job['id'],job['lease_token'],ExecutionResult(text='结果'))
        with db.tx() as c:
            self.assertEqual(c.execute('SELECT COUNT(*) FROM messages').fetchone()[0],0)
            self.assertEqual(runs.get(c,job['id'])['state'],'cancelled')
    def test_notification_failure_preserves_result_for_delivery_retry(self):
        job=self.job()
        delivery=importlib.import_module('verabot.services.scheduled_tasks.delivery')
        with patch.object(clock,'now',return_value=NOW),patch.object(delivery,'notify',side_effect=RuntimeError('unavailable')):
            delivery.commit_result(job['id'],job['lease_token'],ExecutionResult(text='已生成的结果',usage={'total_tokens':9}))
        with db.tx() as c:
            r=runs.get(c,job['id'])
            self.assertEqual(r['state'],'succeeded')
            self.assertEqual(r['result_text'],'已生成的结果')
            self.assertIsNone(r['delivered_at'])
            self.assertEqual(c.execute('SELECT COUNT(*) FROM messages').fetchone()[0],0)
        with patch.object(clock,'now',return_value=NOW):
            self.assertEqual(delivery.flush_pending(),1)
        with db.tx() as c:
            self.assertEqual(c.execute('SELECT COUNT(*) FROM messages').fetchone()[0],1)
            self.assertEqual(c.execute('SELECT SUM(total_tokens) FROM usage_log').fetchone()[0],9)
    def test_revoked_permission_pauses_recurring_task(self):
        job=self.job()
        delivery=importlib.import_module('verabot.services.scheduled_tasks.delivery')
        with patch.object(clock,'now',return_value=NOW):
            delivery.commit_result(job['id'],job['lease_token'],
                ExecutionResult('failed',error_code='permission_revoked',error_summary='权限已撤回'))
        with db.tx() as c:
            task=c.execute('SELECT state,pause_reason FROM scheduled_tasks').fetchone()
            self.assertEqual(tuple(task),('paused','permission_revoked'))
            self.assertEqual(c.execute('SELECT state FROM scheduled_task_runs').fetchone()[0],'failed')
        scheduler=importlib.import_module('verabot.services.scheduled_tasks.scheduler')
        scheduler.tick(NOW+timedelta(days=1))
        with db.tx() as c: self.assertEqual(c.execute('SELECT COUNT(*) FROM scheduled_task_runs').fetchone()[0],1)

if __name__ == '__main__':
    import unittest
    unittest.main()
