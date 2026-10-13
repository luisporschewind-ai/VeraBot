import unittest,json,os,sys,subprocess,threading
from pathlib import Path
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import owned_task_store_test as support
from verabot import db
class ProcessTests(unittest.TestCase):
 setUp=support.OwnedTests.setUp
 tearDown=support.OwnedTests.tearDown
 create=support.OwnedTests.create
 def provider(self,block=False):
  entered=threading.Event();release=threading.Event();calls=[]
  class Handler(BaseHTTPRequestHandler):
   def log_message(self,*args):pass
   def do_POST(self):
    request=json.loads(self.rfile.read(int(self.headers['Content-Length'])));calls.append(request);entered.set()
    if block:release.wait(25)
    body=json.dumps({'choices':[{'message':{'content':'{"action":"completed","text":"Local HTTP report"}'},'finish_reason':'stop'}],'usage':{'prompt_tokens':2,'completion_tokens':3,'total_tokens':5}}).encode()
    try:self.send_response(200);self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
    except (BrokenPipeError,ConnectionResetError):pass
  server=ThreadingHTTPServer(('127.0.0.1',0),Handler);server.daemon_threads=True
  threading.Thread(target=server.serve_forever,daemon=True).start()
  self.addCleanup(server.server_close);self.addCleanup(server.shutdown);self.addCleanup(release.set)
  env=dict(os.environ,DEEPSEEK_API_KEY='local-fake-only',DEEPSEEK_BASE_URL=f'http://127.0.0.1:{server.server_port}')
  cmd=[sys.executable,'-m','verabot.services.owned_tasks','--once']
  return cmd,dict(cwd=Path(__file__).resolve().parents[2],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True),calls,entered,release
 def test_real_subprocess_http_and_idle(self):
  task=self.create();cmd,opts,calls,entered,release=self.provider()
  p=subprocess.run(cmd,timeout=30,**opts);self.assertEqual(p.returncode,0,p.stderr)
  self.assertEqual(len(calls),1);self.assertEqual(self.client.get(f"/api/owned-tasks/{task['id']}").json()['state'],'completed')
  p=subprocess.run(cmd,timeout=30,**opts);self.assertEqual(p.returncode,0,p.stderr);self.assertEqual(len(calls),1)
 def test_killed_process_never_replays(self):
  task=self.create();cmd,opts,calls,entered,release=self.provider(True)
  p=subprocess.Popen(cmd,**opts)
  try:
   self.assertTrue(entered.wait(12));p.kill();p.communicate(timeout=8)
   with db.tx() as c:c.execute("UPDATE owned_steps SET lease_expires_at='2020-01-01T00:00:00+00:00'")
   again=subprocess.run(cmd,timeout=25,**opts);self.assertEqual(again.returncode,0,again.stderr)
   self.assertEqual(len(calls),1);self.assertEqual(self.client.get(f"/api/owned-tasks/{task['id']}").json()['state'],'interrupted')
  finally:
   if p.poll() is None:p.kill();p.communicate()
   release.set()
if __name__=='__main__':unittest.main()
