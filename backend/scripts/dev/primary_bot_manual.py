"""Isolated manual environment: synthetic accounts + localhost fake provider, never real data/models.

Run from backend: python scripts/dev/primary_bot_manual.py --data-dir /tmp/verabot-primary-manual --port 8096
"""
import argparse,os,json,threading,asyncio,sys
from pathlib import Path
from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--data-dir',required=True);p.add_argument('--port',type=int,default=8096);p.add_argument('--check',action='store_true')
 args=p.parse_args();directory=Path(args.data_dir).resolve();marker=directory/'.primary-manual'
 if directory.exists() and any(directory.iterdir()) and not marker.exists():raise SystemExit('Refusing a nonempty directory without the manual-fixture marker')
 directory.mkdir(parents=True,exist_ok=True);marker.touch()
 os.environ.update(VERABOT_DB=str(directory/'primary-manual.db'),VERABOT_DATA_DIR=str(directory),VERABOT_MEMORY_JOBS='0',VERABOT_SCHEDULER='0',DEEPSEEK_API_KEY='localhost-fake-only')
 target=[None]
 class Provider(BaseHTTPRequestHandler):
  def log_message(self,*a):pass
  def do_POST(self):
   request=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
   try:context=json.loads(request['messages'][-1]['content'])
   except (ValueError,KeyError):context={}
   if context.get('completion_criteria')=='回答这项咨询':action={'action':'completed','text':'测试咨询结果：资料已经整理。'}
   elif context.get('input',{}).get('consult_result'):action={'action':'completed','text':'测试任务已完成。这是本地假模型结果，未查询真实资料。'}
   elif context.get('input',{}).get('answer'):action={'action':'consult','bot_id':target[0],'text':'请整理这份测试任务资料。'}
   else:action={'action':'await_user','text':'测试追问：这次任务希望整理哪一周？'}
   body=json.dumps({'choices':[{'message':{'content':json.dumps(action,ensure_ascii=False)},'finish_reason':'stop'}],'usage':{'prompt_tokens':10,'completion_tokens':20,'total_tokens':30}}).encode()
   self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
 provider=ThreadingHTTPServer(('127.0.0.1',0),Provider);provider.daemon_threads=True
 os.environ['DEEPSEEK_BASE_URL']=f'http://127.0.0.1:{provider.server_port}'
 sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
 from verabot import db
 from verabot.core.security import hash_password
 db.init_db()
 with db.tx(immediate=True) as c:
  existing=c.execute("SELECT id FROM users WHERE username='primary-test'").fetchone()
  if not existing:
   uid=c.execute('INSERT INTO users(username,password_hash,created_at) VALUES (?,?,?)',('primary-test',hash_password('primary-test-2026'),db.now_iso())).lastrowid
   owner=c.execute("INSERT INTO bots(user_id,name,allowed_tools,created_at) VALUES (?,'主 Bot 测试伙伴','[\"ask_bot\"]',?)",(uid,db.now_iso())).lastrowid
   peer=c.execute("INSERT INTO bots(user_id,name,accept_delegation,created_at) VALUES (?,'咨询测试伙伴',1,?)",(uid,db.now_iso())).lastrowid
   c.execute('UPDATE bots SET delegate_to=? WHERE id=?',(json.dumps([peer]),owner))
  target[0]=c.execute("SELECT id FROM bots WHERE name='咨询测试伙伴'").fetchone()[0]
 if args.check:
  provider.server_close();print('Isolated schema and synthetic account ready');return
 threading.Thread(target=provider.serve_forever,daemon=True).start()
 from verabot.main import app
 from verabot.services.owned_tasks import worker
 from verabot.services.scheduled_tasks import scheduler
 async def run_tasks():
  import uuid
  owner=uuid.uuid4().hex
  while True:
   scheduler.tick();await worker.process_one(owner);await asyncio.sleep(1)
 async def start():app.state.primary_manual_worker=asyncio.create_task(run_tasks())
 async def stop():
  app.state.primary_manual_worker.cancel();await asyncio.gather(app.state.primary_manual_worker,return_exceptions=True)
  provider.shutdown();provider.server_close()
 app.router.add_event_handler('startup',start);app.router.add_event_handler('shutdown',stop)
 print(f'Fake-only environment: http://127.0.0.1:{args.port}; login primary-test / primary-test-2026')
 import uvicorn
 uvicorn.run(app,host='127.0.0.1',port=args.port)
if __name__=='__main__':main()
