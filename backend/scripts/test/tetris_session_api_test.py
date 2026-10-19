"""Authenticated FastAPI paths with a temporary SQLite database and no worker/model."""
from contextlib import contextmanager
import copy
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from unittest.mock import patch
from uuid import uuid4
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from fastapi import FastAPI
from fastapi.testclient import TestClient
from verabot.api.deps import current_user
from verabot.api.routers.tetris_sessions import router
from verabot.db.migrations.v038_tetris_sessions import migrate
from verabot.db import tetris_session_store as store
from verabot.services.tetris_sessions import rules

class APITests(unittest.TestCase):
    def setUp(self):
        self.directory=tempfile.TemporaryDirectory();self.addCleanup(self.directory.cleanup)
        self.path=Path(self.directory.name)/'api.db'
        with self.tx() as c:
            c.executescript('CREATE TABLE users(id INTEGER PRIMARY KEY);CREATE TABLE bots(id INTEGER PRIMARY KEY,user_id INTEGER);INSERT INTO users VALUES(1),(2);INSERT INTO bots VALUES(11,1),(22,2);')
            migrate(c,37);store.heartbeat(c,'test',100)
        self.app=FastAPI();self.app.include_router(router);self.user=1
        self.app.dependency_overrides[current_user]=lambda:{'id':self.user}
        self.http=TestClient(self.app)
        self.addCleanup(self.http.close)
        self.addCleanup(patch.stopall)
        patch('verabot.services.tetris_sessions.service.tx',self.tx).start()
        patch('verabot.services.tetris_sessions.service.time.time',return_value=100).start()
        g=rules.new(42);rules.apply(g,'start')
        self.body=dict(requestID=str(uuid4()),clientID=str(uuid4()),expectedVersion=0,expectedEpoch=0,botID=11,snapshot=rules.snapshot(g))
        self.prefix='/api/games/tetris/sessions'
    @contextmanager
    def tx(self,**kwargs):
        c=sqlite3.connect(self.path);c.row_factory=sqlite3.Row;c.execute('PRAGMA foreign_keys=ON');c.execute('BEGIN IMMEDIATE')
        try:yield c;c.commit()
        except Exception:c.rollback();raise
        finally:c.close()
    def test_current_round_discovery_is_user_scoped(self):
        self.assertIsNone(self.http.get(self.prefix+'/current').json()['session'])
        created=self.http.post(self.prefix,json=self.body).json()['session']
        self.assertEqual(self.http.get(self.prefix+'/current').json()['session']['id'],created['id'])
        self.user=2
        self.assertIsNone(self.http.get(self.prefix+'/current').json()['session'])
    def test_authentication_required(self):
        self.app.dependency_overrides.clear()
        self.assertEqual(self.http.post(self.prefix,json=self.body).status_code,401)
    def test_create_query_repeat_and_get_does_not_advance(self):
        first=self.http.post(self.prefix,json=self.body)
        self.assertEqual(first.status_code,200,first.text)
        self.assertEqual(first.json(),self.http.post(self.prefix,json=self.body).json())
        sid=first.json()['session']['id']
        before=self.http.get(self.prefix+'/'+sid).json()
        self.assertEqual(before,self.http.get(self.prefix+'/'+sid+'?afterVersion=1').json())
        operation=self.http.get(self.prefix+'/operations/'+self.body['requestID'])
        self.assertEqual(operation.json(),first.json())
        changed={**self.body,'botID':22}
        self.assertEqual(self.http.post(self.prefix,json=changed).status_code,409)
    def test_cross_user_and_other_client_are_read_only(self):
        result=self.http.post(self.prefix,json=self.body).json();session=result['session'];sid=session['id']
        self.user=2
        self.assertEqual(self.http.get(self.prefix+'/'+sid).status_code,404)
        self.assertEqual(self.http.get(self.prefix+'/operations/'+self.body['requestID']).status_code,404)
        self.user=1
        command=dict(requestID=str(uuid4()),clientID=str(uuid4()),expectedVersion=1,expectedEpoch=1,command='reclaim')
        self.assertEqual(self.http.post(self.prefix+'/'+sid+'/commands',json=command).status_code,403)
    def test_validation_and_worker_availability(self):
        invalid=copy.deepcopy(self.body);invalid['snapshot']['ruleVersion']='legacy-1'
        self.assertEqual(self.http.post(self.prefix,json=invalid).status_code,422)
        self.assertEqual(self.http.post(self.prefix,json={**self.body,'extra':'x'*70000}).status_code,413)
        self.assertEqual(self.http.post(self.prefix,json={**self.body,'extra':1}).status_code,422)
        with self.tx() as c:c.execute('DELETE FROM tetris_workers')
        self.assertFalse(self.http.get(self.prefix+'/capabilities').json()['available'])
        self.assertEqual(self.http.post(self.prefix,json=self.body).status_code,503)
        with self.tx() as c:self.assertEqual(c.execute('SELECT count(*) FROM tetris_sessions').fetchone()[0],0)
    def test_pause_is_persisted_and_stale_command_rejected(self):
        session=self.http.post(self.prefix,json=self.body).json()['session'];sid=session['id']
        command=dict(requestID=str(uuid4()),clientID=self.body['clientID'],expectedVersion=1,expectedEpoch=1,command='pauseBot')
        result=self.http.post(self.prefix+'/'+sid+'/commands',json=command)
        self.assertEqual(result.status_code,200,result.text)
        self.assertEqual(result.json()['session']['runState'],'paused')
        self.assertEqual(self.http.post(self.prefix+'/'+sid+'/commands',json=command).json(),result.json())
        command['requestID']=str(uuid4())
        self.assertEqual(self.http.post(self.prefix+'/'+sid+'/commands',json=command).status_code,409)

if __name__=='__main__':unittest.main()
