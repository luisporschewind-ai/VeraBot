import json
import os
import subprocess
import sys
import threading
from datetime import timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch
from scheduled_task_test_support import DBTest, NOW, db
from verabot.services.scheduled_tasks import service, clock

class ProcessTests(DBTest):
    def start_provider(self, block=False):
        entered=threading.Event(); release=threading.Event(); counter=[]
        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                self.rfile.read(int(self.headers['Content-Length']))
                counter.append(1); entered.set()
                if block: release.wait(10)
                body=json.dumps({'choices':[{'message':{'content':'{"state":"succeeded","text":"来自假模型的日报"}'},'finish_reason':'stop'}],'usage':{'total_tokens':3}}).encode()
                try:
                    self.send_response(200); self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(len(body))); self.end_headers(); self.wfile.write(body)
                except (BrokenPipeError,ConnectionResetError): pass
            def log_message(self,*args): pass
        server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
        server.daemon_threads=True
        thread=threading.Thread(target=server.serve_forever,daemon=True); thread.start()
        self.addCleanup(server.server_close); self.addCleanup(server.shutdown); self.addCleanup(release.set)
        return server.server_port, entered, release, counter
    def queue(self):
        with patch.object(clock,'now',return_value=NOW):
            t=service.create(1,self.payload(),'key')
            return service.run_now(1,t['id'],'manual')
    def command(self,port):
        env=dict(os.environ,DEEPSEEK_BASE_URL=f'http://127.0.0.1:{port}',DEEPSEEK_API_KEY='fake-local-only')
        root=Path(__file__).resolve().parents[2]
        return [sys.executable,'-m','verabot.services.scheduled_tasks','--once'],dict(cwd=root,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    def test_process_end_to_end_and_idle(self):
        job=self.queue()
        port,entered,release,counter=self.start_provider()
        command,options=self.command(port)
        p=subprocess.run(command,timeout=30,**options)
        self.assertEqual(p.returncode,0,p.stderr)
        self.assertTrue(entered.is_set())
        with db.tx() as c:
            self.assertEqual(c.execute('SELECT state,result_text FROM scheduled_task_runs').fetchone()[:],('succeeded','来自假模型的日报'))
            self.assertEqual(c.execute('SELECT COUNT(*) FROM messages').fetchone()[0],1)
            self.assertEqual(c.execute('SELECT COUNT(*) FROM notifications').fetchone()[0],1)
        p=subprocess.run(command,timeout=30,**options)
        self.assertEqual(p.returncode,0,p.stderr)
        self.assertEqual(len(counter),1)
    def test_killed_worker_restart_does_not_repeat_provider(self):
        job=self.queue()
        port,entered,release,counter=self.start_provider(block=True)
        command,options=self.command(port)
        p=subprocess.Popen(command,**options)
        self.addCleanup(lambda: p.kill() if p.poll() is None else None)
        self.assertTrue(entered.wait(15))
        p.kill(); p.communicate(timeout=10)
        with db.tx() as c:
            c.execute("UPDATE scheduled_task_runs SET lease_expires_at=?",(clock.iso(clock.now()-timedelta(seconds=1)),))
        p2=subprocess.run(command,timeout=30,**options)
        self.assertEqual(p2.returncode,0,p2.stderr)
        with db.tx() as c:
            self.assertEqual(c.execute('SELECT state FROM scheduled_task_runs').fetchone()[0],'interrupted')
        self.assertEqual(len(counter),1)

if __name__ == '__main__':
    import unittest
    unittest.main()
