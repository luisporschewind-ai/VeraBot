"""Real temporary SQLite transactions. Does not import/start the live API."""
import copy
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from uuid import uuid4
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from verabot.db import tetris_session_store as store
from verabot.db.migrations import v038_tetris_sessions as migration
from verabot.services.tetris_sessions import rules

class StoreTests(unittest.TestCase):
    def setUp(self):
        self.directory=tempfile.TemporaryDirectory();self.addCleanup(self.directory.cleanup)
        self.path=Path(self.directory.name)/'sessions.db'
        self.c=sqlite3.connect(self.path);self.addCleanup(self.c.close)
        self.c.row_factory=sqlite3.Row;self.c.execute('PRAGMA foreign_keys=ON')
        self.c.executescript('CREATE TABLE users(id INTEGER PRIMARY KEY); CREATE TABLE bots(id INTEGER PRIMARY KEY,user_id INTEGER REFERENCES users(id)); INSERT INTO users VALUES(1),(2); INSERT INTO bots VALUES(11,1),(22,2);')
        migration.migrate(self.c,37)
        store.heartbeat(self.c,'worker',100)
        self.client=str(uuid4())
        game=rules.new(42);rules.apply(game,'start')
        self.body=dict(requestID=str(uuid4()),clientID=self.client,expectedVersion=0,expectedEpoch=0,botID=11,snapshot=rules.snapshot(game))
    def handoff(self):return store.create_handoff(self.c,1,self.body,100)
    def command(self,session,kind,**extra):
        return dict(requestID=str(uuid4()),clientID=self.client,expectedVersion=session['version'],expectedEpoch=session['controlEpoch'],command=kind) | extra
    def test_deleting_bot_does_not_block_or_delete_the_round(self):
        session=self.handoff()['session']
        self.c.execute('DELETE FROM bots WHERE id=11')
        self.assertIsNone(store.get_session(self.c,1,session['id'])['botID'])
        self.assertEqual(self.c.execute('PRAGMA foreign_key_check').fetchall(),[])
    def test_capacity_and_body_size_reject_before_creating(self):
        with self.assertRaises(store.SessionError) as error:store.create_handoff(self.c,1,{**self.body,'padding':'x'*70000},100)
        self.assertEqual(error.exception.status,413)
        for uid in range(100,100+store.MAX_SESSIONS):
            self.c.execute('INSERT INTO users VALUES(?)',(uid,))
            self.c.execute('INSERT INTO bots VALUES(?,?)',(uid*10,uid))
            store.create_handoff(self.c,uid,{**self.body,'requestID':str(uuid4()),'botID':uid*10},100)
        with self.assertRaises(store.SessionError) as error:store.create_handoff(self.c,2,{**self.body,'requestID':str(uuid4()),'botID':22},100)
        self.assertEqual(error.exception.status,503)
        self.assertEqual(self.c.execute('SELECT count(*) FROM tetris_sessions').fetchone()[0],store.MAX_SESSIONS)
    def test_event_page_is_bounded_with_snapshot_fallback(self):
        session=self.handoff()['session'];lease=store.claim(self.c,'one',100)
        game=rules.restore(lease['snapshot']);events=[]
        for index in range(120):events+=rules.apply(game,'moveLeft' if index%2==0 else 'moveRight')
        self.assertTrue(store.commit_batch(self.c,session['id'],1,1,lease['leaseToken'],rules.snapshot(game),events,100.1))
        overflow=store.get_session(self.c,1,session['id'],1)
        self.assertTrue(overflow['snapshotFallback']);self.assertEqual(overflow['events'],[])
        recent=store.get_session(self.c,1,session['id'],111)
        self.assertFalse(recent['snapshotFallback']);self.assertEqual(len(recent['events']),10)
        self.assertLess(len(json.dumps(recent).encode()),65536)
    def test_cadence_is_anchored_but_downtime_is_not_caught_up(self):
        session=self.handoff()['session'];lease=store.claim(self.c,'one',100)
        game=rules.restore(lease['snapshot']);events=rules.advance(game,100)
        self.assertTrue(store.commit_batch(self.c,session['id'],1,1,lease['leaseToken'],rules.snapshot(game),events,100.03))
        self.assertAlmostEqual(self.c.execute('SELECT next_due FROM tetris_sessions WHERE id=?',(session['id'],)).fetchone()[0],100.1)
        lease=store.claim(self.c,'two',3700)
        game=rules.restore(lease['snapshot']);events=rules.advance(game,100)
        self.assertTrue(store.commit_batch(self.c,session['id'],2,1,lease['leaseToken'],rules.snapshot(game),events,3700))
        self.assertAlmostEqual(self.c.execute('SELECT next_due FROM tetris_sessions WHERE id=?',(session['id'],)).fetchone()[0],3700.1)
    def test_idempotency_payload_identity_and_schema(self):
        first=self.handoff()
        self.assertEqual(first,self.handoff())
        with self.assertRaises(store.SessionError) as error:store.create_handoff(self.c,1,{**self.body,'botID':22},100)
        self.assertEqual(error.exception.status,409)
        self.assertEqual(store.get_operation(self.c,1,self.body['requestID']),first)
        migration.migrate(self.c,38)
        self.assertEqual(self.c.execute('PRAGMA integrity_check').fetchone()[0],'ok')
        self.assertEqual(self.c.execute('PRAGMA foreign_key_check').fetchall(),[])
    def test_ownership_origin_and_version(self):
        session=self.handoff()['session'];sid=session['id']
        with self.assertRaises(store.SessionError) as error:store.get_session(self.c,2,sid)
        self.assertEqual(error.exception.status,404)
        with self.assertRaises(store.SessionError) as error:store.apply_command(self.c,1,sid,self.command(session,'reclaim',clientID=str(uuid4())),100)
        self.assertEqual(error.exception.status,403)
        stale=self.command(session,'pauseBot');stale['expectedVersion']=2
        with self.assertRaises(store.SessionError) as error:store.apply_command(self.c,1,sid,stale,100)
        self.assertEqual(error.exception.status,409)
        self.assertEqual(store.get_session(self.c,1,sid)['version'],1)
    def test_admission_needs_worker_and_one_active_bot_round(self):
        with self.assertRaises(store.SessionError) as error:store.create_handoff(self.c,1,self.body,111)
        self.assertEqual(error.exception.status,503)
        self.handoff()
        with self.assertRaises(store.SessionError) as error:store.create_handoff(self.c,1,{**self.body,'requestID':str(uuid4())},100)
        self.assertEqual(error.exception.status,409)
        self.assertEqual(self.c.execute('SELECT count(*) FROM tetris_sessions').fetchone()[0],1)
    def test_claim_and_commit_fence_stale_work(self):
        session=self.handoff()['session'];sid=session['id']
        lease=store.claim(self.c,'one',100)
        self.assertIsNotNone(lease)
        self.assertIsNone(store.claim(self.c,'two',100))
        game=rules.restore(lease['snapshot']);events=rules.advance(game,100)
        self.assertTrue(store.commit_batch(self.c,sid,1,1,lease['leaseToken'],rules.snapshot(game),events,100.1))
        self.assertFalse(store.commit_batch(self.c,sid,1,1,lease['leaseToken'],rules.snapshot(game),events,100.2))
        updated=store.get_session(self.c,1,sid)
        store.apply_command(self.c,1,sid,self.command(updated,'pauseBot'),100.2)
        self.assertFalse(store.commit_batch(self.c,sid,2,1,lease['leaseToken'],rules.snapshot(game),events,100.3))
    def test_expired_lease_and_reclaim_pending_cannot_accept_ordinary_batch(self):
        session=self.handoff()['session'];lease=store.claim(self.c,'one',100)
        self.assertFalse(store.commit_batch(self.c,session['id'],1,1,lease['leaseToken'],lease['snapshot'],[],110))
        pending=store.apply_command(self.c,1,session['id'],self.command(session,'reclaim'),100.1)
        self.assertEqual(pending['status'],'pending')
        next_lease=store.claim(self.c,'two',100.1)
        self.assertIsNotNone(next_lease)
        self.assertFalse(store.commit_batch(self.c,session['id'],next_lease['version'],next_lease['controlEpoch'],next_lease['leaseToken'],next_lease['snapshot'],[],100.2))
        game=rules.restore(next_lease['snapshot']);events=rules.apply(game,'pause')
        self.assertTrue(store.commit_batch(self.c,session['id'],next_lease['version'],next_lease['controlEpoch'],next_lease['leaseToken'],rules.snapshot(game),events,100.2,transition_only=True))
        result=store.get_operation(self.c,1,pending['requestID'])
        self.assertEqual(result['status'],'committed');self.assertEqual(result['session']['controller'],'player')
        self.assertEqual(result['session']['controlEpoch'],2)
    def test_player_clearing_handoff_keeps_clear_contribution(self):
        fixture=json.loads((Path(__file__).resolve().parents[3]/'docs/contracts/tetris-v2-fixtures.json').read_text())['cases']
        game=rules.restore(next(case for case in fixture if case['name']=='four-lines-score-once')['initial'])
        rules.apply(game,'hardDrop')
        self.body['snapshot']=rules.snapshot(game)
        session=self.handoff()['session'];lease=store.claim(self.c,'one',100)
        events=rules.advance(game,180)
        self.assertTrue(store.commit_batch(self.c,session['id'],1,1,lease['leaseToken'],rules.snapshot(game),events,100.1))
        contribution=store.get_session(self.c,1,session['id'])['contribution']
        self.assertEqual(contribution,dict(playerScore=832,playerLines=4,botScore=0,botLines=0))
    def test_non_owner_bot_is_rejected(self):
        with self.assertRaises(store.SessionError) as error:store.create_handoff(self.c,1,{**self.body,'botID':22},100)
        self.assertEqual(error.exception.status,404)
    def test_commands_pause_resume_and_change_bot_are_durable(self):
        session=self.handoff()['session'];sid=session['id']
        pause=self.command(session,'pauseBot')
        result=store.apply_command(self.c,1,sid,pause,100.1)
        self.assertEqual(result['session']['runState'],'paused')
        self.assertEqual(result,store.apply_command(self.c,1,sid,pause,100.2))
        resumed=store.apply_command(self.c,1,sid,self.command(result['session'],'resumeBot'),100.3)
        self.assertEqual(resumed['session']['runState'],'running')
        end=store.apply_command(self.c,1,sid,self.command(resumed['session'],'end'),100.4)
        self.assertEqual(end['session']['runState'],'over')
        self.assertIsNone(store.claim(self.c,'one',101))

if __name__=='__main__':unittest.main()
