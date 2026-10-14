from datetime import timedelta
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import patch
from scheduled_task_test_support import DBTest, NOW, db
from verabot.services.scheduled_tasks import service, schedule, clock
import importlib

class SchedulerTests(DBTest):
    def task(self, **changes):
        p=self.payload(); p.update(changes)
        with patch.object(clock,'now',return_value=NOW):
            return service.create(1,p,'key')
    def test_duplicate_tick_and_busy(self):
        scheduler=importlib.import_module('verabot.services.scheduled_tasks.scheduler')
        t=self.task()
        now=NOW+timedelta(minutes=1)
        with ThreadPoolExecutor(2) as pool:
            list(pool.map(lambda _:scheduler.tick(now),range(2)))
        with db.tx() as c:
            self.assertEqual(c.execute('SELECT COUNT(*) FROM scheduled_task_runs').fetchone()[0],1)
        scheduler.tick(now+timedelta(days=1))
        with db.tx() as c:
            self.assertEqual(c.execute("SELECT COUNT(*) FROM scheduled_task_runs WHERE state='queued'").fetchone()[0],1)
            self.assertEqual(c.execute("SELECT error_code FROM scheduled_task_runs WHERE state='skipped'").fetchone()[0],'previous_run_active')
    def test_skip_and_latest(self):
        scheduler=importlib.import_module('verabot.services.scheduled_tasks.scheduler')
        t=self.task()
        scheduler.tick(NOW+timedelta(days=3,hours=12))
        with db.tx() as c:
            self.assertEqual(c.execute('SELECT state FROM scheduled_task_runs').fetchone()[0],'skipped')
            c.execute("UPDATE scheduled_tasks SET next_run_at_utc=?,misfire_policy='latest'", (clock.iso(NOW+timedelta(minutes=1)),))
        scheduler.tick(NOW+timedelta(days=4,hours=12))
        with db.tx() as c:
            self.assertEqual(c.execute("SELECT COUNT(*) FROM scheduled_task_runs WHERE state='queued'").fetchone()[0],1)
            self.assertGreater(clock.parse(c.execute('SELECT next_run_at_utc FROM scheduled_tasks').fetchone()[0]), NOW+timedelta(days=4,hours=12))
    def test_dst_and_clock_backwards(self):
        task={'timezone':'America/New_York','start_at_utc':'2026-03-07T07:30:00+00:00','rrule':'FREQ=DAILY'}
        nxt=schedule.next_after(task,clock.parse(task['start_at_utc']))
        self.assertEqual(nxt.isoformat(),'2026-03-09T06:30:00+00:00')
        task={'timezone':'America/New_York','start_at_utc':'2026-10-31T05:30:00+00:00','rrule':'FREQ=DAILY'}
        first=schedule.next_after(task,clock.parse(task['start_at_utc']))
        self.assertEqual(first.isoformat(),'2026-11-01T05:30:00+00:00')
        self.assertEqual(schedule.next_after(task,first).isoformat(),'2026-11-02T06:30:00+00:00')
        scheduler=importlib.import_module('verabot.services.scheduled_tasks.scheduler')
        self.task()
        scheduler.tick(NOW+timedelta(minutes=1))
        scheduler.tick(NOW)
        with db.tx() as c:
            self.assertEqual(c.execute('SELECT COUNT(*) FROM scheduled_task_runs').fetchone()[0],1)
    def test_grace_and_one_off_latest_age(self):
        scheduler=importlib.import_module('verabot.services.scheduled_tasks.scheduler')
        self.task(repeat='once')
        scheduler.tick(NOW+timedelta(minutes=11))
        with db.tx() as c:
            self.assertEqual(c.execute('SELECT state FROM scheduled_task_runs').fetchone()[0],'queued')
        self.setUp()
        self.task(repeat='once',misfire_policy='latest')
        scheduler.tick(NOW+timedelta(days=2))
        with db.tx() as c:
            self.assertEqual(c.execute('SELECT state FROM scheduled_task_runs').fetchone()[0],'skipped')
            self.assertEqual(c.execute('SELECT state FROM scheduled_tasks').fetchone()[0],'completed')
    def test_deleted_bot_pauses_without_waiting_for_due(self):
        scheduler=importlib.import_module('verabot.services.scheduled_tasks.scheduler')
        self.task()
        with db.tx() as c: c.execute('DELETE FROM bots WHERE id=1')
        scheduler.tick(NOW)
        with db.tx() as c:
            self.assertEqual(c.execute('SELECT state,pause_reason FROM scheduled_tasks').fetchone()[:],('paused','bot_deleted'))
    def test_resume_after_clock_rollback_skips_recorded_occurrence(self):
        scheduler=importlib.import_module('verabot.services.scheduled_tasks.scheduler')
        t=self.task()
        due=NOW+timedelta(minutes=1)
        scheduler.tick(due)
        with db.tx() as c: c.execute("UPDATE scheduled_task_runs SET state='succeeded'")
        with patch.object(clock,'now',return_value=due):
            paused=service.transition(1,t['id'],'pause',1)
        with patch.object(clock,'now',return_value=NOW):
            resumed=service.transition(1,t['id'],'resume',paused['version'])
        self.assertGreater(clock.parse(resumed['next_run_at_utc']),due)
        scheduler.tick(due)
        with db.tx() as c: self.assertEqual(c.execute('SELECT COUNT(*) FROM scheduled_task_runs').fetchone()[0],1)
    def test_duplicate_due_record_does_not_block_other_tasks(self):
        scheduler=importlib.import_module('verabot.services.scheduled_tasks.scheduler')
        self.task()
        due=NOW+timedelta(minutes=1)
        scheduler.tick(due)
        with db.tx() as c:
            c.execute("UPDATE scheduled_task_runs SET state='succeeded'")
            c.execute("UPDATE scheduled_tasks SET next_run_at_utc=?",(clock.iso(due),))
        with patch.object(clock,'now',return_value=NOW):
            service.create(1,self.payload(),'second-key')
        scheduler.tick(due)
        with db.tx() as c:
            self.assertEqual(c.execute("SELECT COUNT(*) FROM scheduled_task_runs WHERE state='queued'").fetchone()[0],1)
            self.assertEqual(c.execute('SELECT COUNT(*) FROM scheduled_task_runs').fetchone()[0],2)

if __name__ == '__main__':
    import unittest
    unittest.main()
