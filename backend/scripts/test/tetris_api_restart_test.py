"""Actual API restart while a separate worker continues a temporary same round."""
import json
import os
from pathlib import Path
import signal
import socket
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest
from uuid import uuid4
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
import httpx
from verabot.db.migrations.v038_tetris_sessions import migrate
from verabot.services.tetris_sessions import rules
BACKEND=Path(__file__).resolve().parents[2]
class RestartTests(unittest.TestCase):
    def test_api_restart_retains_authority_and_original_idempotent_result(self):
        with tempfile.TemporaryDirectory(prefix='verabot-tetris-load-restart-') as folder:
            root=Path(folder);path=root/'test.db';c=sqlite3.connect(path)
            c.executescript('CREATE TABLE users(id INTEGER PRIMARY KEY);CREATE TABLE bots(id INTEGER PRIMARY KEY,user_id INTEGER);INSERT INTO users VALUES(100);INSERT INTO bots VALUES(100,100);')
            migrate(c,37);c.commit()
            env={**os.environ,'VERABOT_DB':str(path),'VERABOT_TETRIS_LOAD_TEST':'1','VERABOT_JWT_SECRET':'isolated-restart','DEEPSEEK_API_KEY':'','OPENAI_API_KEY':''}
            processes=[];logs=[]
            def start(module,*args):
                log=open(root/f'{len(logs)}.log','w');logs.append(log)
                p=subprocess.Popen([sys.executable,'-m',module,*args],cwd=BACKEND,env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True);processes.append(p);return p
            def stop(p):
                if p.poll() is not None:return
                p.terminate()
                try:p.wait(timeout=8)
                except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait(timeout=5)
            def wait(function):
                deadline=time.monotonic()+12
                while time.monotonic()<deadline:
                    try:
                        value=function()
                        if value:return value
                    except (httpx.HTTPError,sqlite3.OperationalError):pass
                    time.sleep(.05)
                self.fail('API/worker restart did not become ready')
            with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
            args=('scripts.test.tetris_load_api:app','--host','127.0.0.1','--port',str(port),'--no-access-log')
            try:
                api=start('uvicorn',*args);worker=start('verabot.services.tetris_sessions')
                with httpx.Client(base_url=f'http://127.0.0.1:{port}',headers={'X-Test-User':'100'},timeout=2) as client:
                    prefix='/api/games/tetris/sessions'
                    wait(lambda:client.get(prefix+'/capabilities').json().get('workerReady'))
                    game=rules.new(42);rules.apply(game,'start')
                    body=dict(requestID=str(uuid4()),clientID=str(uuid4()),expectedVersion=0,expectedEpoch=0,botID=100,snapshot=rules.snapshot(game))
                    result=client.post(prefix,json=body);self.assertEqual(result.status_code,200)
                    original=result.json();sid=original['session']['id']
                    def version():return c.execute('SELECT version FROM tetris_sessions WHERE id=?',(sid,)).fetchone()[0]
                    before=wait(lambda:version() if version()>1 else None)
                    os.killpg(api.pid,signal.SIGKILL);api.wait(timeout=5)
                    wait(lambda:version()>before)
                    replacement=start('uvicorn',*args)
                    wait(lambda:client.get(prefix+'/capabilities').status_code==200)
                    retry=client.post(prefix,json=body)
                    self.assertEqual(retry.status_code,200);self.assertEqual(retry.json(),original)
                    current=client.get(prefix+'/'+sid).json()
                    self.assertGreater(current['version'],before)
                    self.assertEqual(c.execute('SELECT count(*) FROM tetris_sessions').fetchone()[0],1)
                    self.assertIsNone(worker.poll());self.assertIsNone(replacement.poll())
            finally:
                for p in reversed(processes):stop(p)
                for log in logs:log.close()
                c.close()
if __name__=='__main__':unittest.main()
