"""Worker control/race tests against temporary real SQLite; fake clock/executor only."""
from concurrent.futures import Future
from contextlib import contextmanager
import json
from pathlib import Path
import sqlite3
import sys
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
import tetris_session_store_test as store_fixture
from verabot.db import tetris_session_store as store
from verabot.services.tetris_sessions import rules,worker
from verabot.services.tetris_sessions.planner import Plan,PlannedAction

class ImmediateExecutor:
    def submit(self,function,*args,**kwargs):
        result=Future()
        try:result.set_result(function(*args,**kwargs))
        except Exception as error:result.set_exception(error)
        return result
class DeferredExecutor:
    def __init__(self):self.jobs=[]
    def submit(self,*args,**kwargs):
        future=Future();self.jobs.append(future);return future

class WorkerTests(unittest.TestCase):
    handoff=store_fixture.StoreTests.handoff
    command=store_fixture.StoreTests.command
    def setUp(self):
        store_fixture.StoreTests.setUp(self);self.c.commit();self.fail_commit=False
    @contextmanager
    def tx(self,**kwargs):
        c=sqlite3.connect(self.path);c.row_factory=sqlite3.Row;c.execute('PRAGMA foreign_keys=ON');c.execute('BEGIN IMMEDIATE')
        try:
            yield c
            row=c.execute('SELECT max(version) FROM tetris_sessions').fetchone()
            if self.fail_commit and row[0] and row[0]>1:
                self.fail_commit=False;raise sqlite3.OperationalError('injected commit failure')
            c.commit()
        except Exception:c.rollback();raise
        finally:c.close()
    def make(self,name,executor=None):
        result=worker.Worker(transaction=self.tx,owner=name,executor=executor or ImmediateExecutor(),clock=lambda:100)
        self.addCleanup(result.close);return result
    def start(self):
        session=self.handoff()['session'];self.c.commit();return session
    def test_read_only_database_never_publishes_and_recovers_from_last_commit(self):
        session=self.start()
        @contextmanager
        def readonly(**kwargs):
            c=sqlite3.connect(f'file:{self.path}?mode=ro',uri=True);c.row_factory=sqlite3.Row
            try:
                c.execute('BEGIN IMMEDIATE')
                yield c
                c.commit()
            finally:c.close()
        subject=self.make('read-only');subject.transaction=readonly
        result=subject.tick(100)
        self.assertEqual(result.published,())
        self.assertGreater(result.errors,0)
        self.assertTrue(any('readonly' in item.lower() for item in result.errorKinds))
        self.assertEqual(store.get_session(self.c,1,session['id'])['version'],1)
        subject.transaction=self.tx
        subject.tick(3700)
        self.assertEqual(store.get_session(self.c,1,session['id'])['latestSnapshot']['logicalTimeMs'],100)
    def test_planning_service_failure_does_not_stop_gravity(self):
        class BrokenExecutor:
            def submit(self,*args,**kwargs):raise RuntimeError('planner unavailable')
        session=self.start();subject=self.make('one',BrokenExecutor())
        result=subject.tick(100)
        self.assertGreater(result.errors,0)
        self.assertTrue(any('planning:RuntimeError:planner unavailable' in value for value in result.errorKinds))
        self.assertEqual(store.get_session(self.c,1,session['id'])['latestSnapshot']['logicalTimeMs'],100)
    def test_two_workers_do_not_double_advance_and_no_offline_catchup(self):
        session=self.start();one=self.make('one');two=self.make('two')
        one.tick(100);two.tick(100)
        first=store.get_session(self.c,1,session['id'])
        self.assertEqual(first['latestSnapshot']['logicalTimeMs'],100)
        one.close();two.tick(3700)
        second=store.get_session(self.c,1,session['id'])
        self.assertEqual(second['latestSnapshot']['logicalTimeMs'],200)
    def test_pending_clear_reclaim_survives_worker_restart_and_counts_once(self):
        fixtures=json.loads((Path(__file__).resolve().parents[3]/'docs/contracts/tetris-v2-fixtures.json').read_text())['cases']
        game=rules.restore(next(case for case in fixtures if case['name']=='four-lines-score-once')['initial'])
        rules.apply(game,'hardDrop');self.body['snapshot']=rules.snapshot(game)
        session=self.start();pending=store.apply_command(self.c,1,session['id'],self.command(session,'reclaim'),100);self.c.commit()
        one=self.make('one');one.tick(100)
        halfway=store.get_operation(self.c,1,pending['requestID'])
        self.assertEqual(halfway['status'],'pending')
        one.close();two=self.make('two');two.tick(100.1)
        result=store.get_operation(self.c,1,pending['requestID'])
        self.assertEqual(result['status'],'committed')
        latest=result['session'];self.assertEqual(latest['controller'],'player');self.assertEqual(latest['runState'],'paused')
        self.assertEqual(latest['latestSnapshot']['logicalTimeMs'],180)
        self.assertEqual(latest['latestSnapshot']['score'],832)
        self.assertEqual(latest['contribution'],dict(playerScore=832,playerLines=4,botScore=0,botLines=0))
        two.tick(100.2)
        self.assertEqual(store.get_session(self.c,1,session['id']),latest)
    def test_commit_failure_never_publishes_or_advances_durable_snapshot(self):
        session=self.start();subject=self.make('one');self.fail_commit=True
        result=subject.tick(100)
        self.assertEqual(result.published,())
        self.assertGreater(result.errors,0)
        self.assertTrue(any('commit:OperationalError' in value for value in result.errorKinds))
        self.assertEqual(store.get_session(self.c,1,session['id'])['latestSnapshot']['logicalTimeMs'],0)
        subject.tick(100.1)
        self.assertEqual(store.get_session(self.c,1,session['id'])['latestSnapshot']['logicalTimeMs'],100)
    def test_late_plan_after_pause_resume_is_discarded(self):
        session=self.start();executor=DeferredExecutor();subject=self.make('one',executor);subject.tick(100)
        current=store.get_session(self.c,1,session['id'])
        paused=store.apply_command(self.c,1,session['id'],self.command(current,'pauseBot'),100.01)['session']
        store.apply_command(self.c,1,session['id'],self.command(paused,'resumeBot'),100.02);self.c.commit()
        executor.jobs[0].set_result(Plan(2,1,100,(PlannedAction('hardDrop',100),),1,False))
        subject.tick(100.1)
        self.assertEqual(store.get_session(self.c,1,session['id'])['latestSnapshot']['lockedPieces'],0)
    def test_control_change_during_simulation_rejects_the_whole_batch(self):
        session=self.start();subject=self.make('one');original=rules.advance;changed=False
        def advance(game,elapsed):
            nonlocal changed
            if not changed:
                changed=True
                with self.tx() as c:store.apply_command(c,1,session['id'],self.command(session,'pauseBot'),100.01)
            return original(game,elapsed)
        with patch.object(rules,'advance',side_effect=advance):result=subject.tick(100)
        self.assertEqual(result.published,())
        latest=store.get_session(self.c,1,session['id'])
        self.assertEqual(latest['runState'],'paused');self.assertEqual(latest['latestSnapshot']['logicalTimeMs'],0)
    def test_bot_plays_without_models_and_contributions_sum_to_score(self):
        session=self.start();subject=self.make('one')
        for index in range(50):subject.tick(100+index*.1)
        latest=store.get_session(self.c,1,session['id']);score=latest['latestSnapshot']['score'];parts=latest['contribution']
        self.assertGreater(latest['latestSnapshot']['lockedPieces'],0)
        self.assertEqual(parts['playerScore']+parts['botScore'],score)
        self.assertEqual(parts['playerLines']+parts['botLines'],latest['latestSnapshot']['lines'])

if __name__=='__main__':unittest.main()
