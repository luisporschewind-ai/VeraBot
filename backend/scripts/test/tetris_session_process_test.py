"""Two real independently launched workers, killed as isolated process groups.
Only temporary DB/data paths; provider keys are removed from the child environment.
"""
import json
import os
from pathlib import Path
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest
from uuid import uuid4
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from verabot.db.migrations.v038_tetris_sessions import migrate
from verabot.db import tetris_session_store as store
from verabot.services.tetris_sessions import rules
BACKEND=Path(__file__).resolve().parents[2]

class ProcessTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.path=Path(self.tmp.name)/'process.db'
        self.c=sqlite3.connect(self.path);self.c.row_factory=sqlite3.Row;self.addCleanup(self.c.close)
        self.c.execute('PRAGMA foreign_keys=ON')
        self.c.executescript('CREATE TABLE users(id INTEGER PRIMARY KEY);CREATE TABLE bots(id INTEGER PRIMARY KEY,user_id INTEGER);INSERT INTO users VALUES(1);INSERT INTO bots VALUES(11,1);')
        migrate(self.c,37);self.c.commit()
        self.env={**os.environ,'VERABOT_DB':str(self.path),'VERABOT_DATA_DIR':self.tmp.name,'VERABOT_JWT_SECRET':'isolated-test-secret'}
        for key in ('DEEPSEEK_API_KEY','OPENAI_API_KEY'):self.env.pop(key,None)
    def start(self):
        log=open(Path(self.tmp.name)/f'worker-{uuid4()}.log','w')
        self.addCleanup(log.close)
        process=subprocess.Popen([sys.executable,'-m','verabot.services.tetris_sessions'],cwd=BACKEND,env=self.env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
        self.addCleanup(self.stop,process)
        return process
    @staticmethod
    def stop(process):
        if process.poll() is not None:return
        try:os.killpg(process.pid,signal.SIGTERM)
        except ProcessLookupError:pass
        try:process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid,signal.SIGKILL);process.wait(timeout=5)
    def wait(self,predicate,seconds=10):
        deadline=time.monotonic()+seconds
        while time.monotonic()<deadline:
            result=predicate()
            if result:return result
            time.sleep(.05)
        self.fail('timed out waiting for isolated worker progress')
    def handoff(self):
        game=rules.new(42);rules.apply(game,'start')
        body=dict(requestID=str(uuid4()),clientID=str(uuid4()),expectedVersion=0,expectedEpoch=0,botID=11,snapshot=rules.snapshot(game))
        self.c.execute('BEGIN IMMEDIATE')
        result=store.create_handoff(self.c,1,body,time.time());self.c.commit()
        return result['session']['id']
    def test_two_real_workers_recover_a_killed_owner_without_catchup(self):
        one=self.start();two=self.start()
        self.wait(lambda:self.c.execute('SELECT count(*) FROM tetris_workers WHERE heartbeat>?',(time.time()-3,)).fetchone()[0]==2)
        sid=self.handoff()
        self.wait(lambda:store.get_session(self.c,1,sid)['latestSnapshot']['lockedPieces']>0)
        row=dict(self.c.execute('SELECT * FROM tetris_sessions WHERE id=?',(sid,)).fetchone())
        before=json.loads(row['snapshot_json'])['logicalTimeMs']
        owner=one if row['lease_owner'].startswith(str(one.pid)+':') else two
        survivor=two if owner is one else one
        os.killpg(owner.pid,signal.SIGKILL);owner.wait(timeout=5)
        def recovered():
            current=self.c.execute('SELECT lease_owner,snapshot_json FROM tetris_sessions WHERE id=?',(sid,)).fetchone()
            if current['lease_owner'] and current['lease_owner'].startswith(str(survivor.pid)+':'):
                return json.loads(current['snapshot_json'])
        snapshot=self.wait(recovered,seconds=15)
        self.assertLess(snapshot['logicalTimeMs']-before,1000)
        self.assertGreater(snapshot['logicalTimeMs'],before)
        self.assertIsNone(survivor.poll())
    def test_once_and_status_need_no_model_and_do_not_spawn_an_api(self):
        args=[sys.executable,'-m','verabot.services.tetris_sessions']
        once=subprocess.run(args+['--once'],cwd=BACKEND,env=self.env,capture_output=True,text=True,timeout=10)
        self.assertEqual(once.returncode,0,once.stderr)
        status=subprocess.run(args+['--status'],cwd=BACKEND,env=self.env,capture_output=True,text=True,timeout=10)
        self.assertEqual(status.returncode,0,status.stderr)
        result=json.loads(status.stdout)
        self.assertEqual(result['ruleVersion'],'vera-tetris-2');self.assertFalse(result['workerReady'])
        self.assertIn('fixtureSHA256',result)

if __name__=='__main__':unittest.main()
