import os, sys, tempfile, unittest
from pathlib import Path
_tmp=tempfile.TemporaryDirectory(prefix='vb_primary_')
os.environ['VERABOT_DB']=str(Path(_tmp.name)/'test.db')
os.environ['VERABOT_DATA_DIR']=_tmp.name
os.environ['VERABOT_MEMORY_JOBS']='0'
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from verabot import db
from verabot.main import app
from verabot.api.deps import current_user
from fastapi.testclient import TestClient

class PrimaryTests(unittest.TestCase):
 def setUp(self):
  db.init_db()
  with db.tx() as c:
   for table in ('usage_log','notifications','messages'):
    c.execute('DELETE FROM '+table)
   c.execute('DELETE FROM users')
   self.uid=c.execute("INSERT INTO users(username,password_hash,created_at) VALUES ('p','x','now')").lastrowid
   other=c.execute("INSERT INTO users(username,password_hash,created_at) VALUES ('o','x','now')").lastrowid
   self.bid=c.execute("INSERT INTO bots(user_id,name,created_at) VALUES (?,'A','now')",(self.uid,)).lastrowid
   self.foreign=c.execute("INSERT INTO bots(user_id,name,created_at) VALUES (?,'B','now')",(other,)).lastrowid
  app.dependency_overrides[current_user]=lambda:{'id':self.uid}
  self.client=TestClient(app)
 def tearDown(self):app.dependency_overrides.clear();self.client.close()
 def test_selection_does_not_enable_and_version_conflicts(self):
  r=self.client.get('/api/primary-bot');self.assertEqual(r.status_code,200)
  s=r.json();self.assertIsNone(s['primary_bot_id']);self.assertFalse(s['active_enabled'])
  r=self.client.patch('/api/primary-bot',json={'primary_bot_id':self.bid,'expected_version':s['version']})
  self.assertEqual(r.status_code,200);self.assertFalse(r.json()['active_enabled'])
  self.assertEqual(self.client.patch('/api/primary-bot',json={'primary_bot_id':None,'expected_version':s['version']}).status_code,409)
 def test_ownership_and_bad_budget(self):
  for bid in (self.foreign,999999):
   self.assertEqual(self.client.patch('/api/primary-bot',json={'primary_bot_id':bid,'expected_version':1}).status_code,404)
  self.assertEqual(self.client.patch('/api/primary-bot',json={'daily_token_limit':0,'expected_version':1}).status_code,422)
 def test_delete_clears_identity_and_advances_version(self):
  self.client.patch('/api/primary-bot',json={'primary_bot_id':self.bid,'expected_version':1})
  with db.tx() as c:
   from verabot.db import bot_store
   bot_store.delete(c,self.uid,self.bid)
  s=self.client.get('/api/primary-bot').json();self.assertIsNone(s['primary_bot_id']);self.assertEqual(s['version'],3)
 def test_cancel_and_legacy_user(self):
  from verabot.services.users import load_public
  self.assertIn('primary_bot_id',load_public(self.uid))
  s=self.client.patch('/api/primary-bot',json={'primary_bot_id':self.bid,'expected_version':1}).json()
  r=self.client.patch('/api/primary-bot',json={'primary_bot_id':None,'expected_version':s['version']})
  self.assertEqual(r.status_code,200);self.assertIsNone(r.json()['primary_bot_id'])
 def test_no_identity_cannot_enable(self):
  self.assertEqual(self.client.patch('/api/primary-bot',json={'active_enabled':True,'expected_version':1}).status_code,422)
 def test_idempotent_migration(self):
  db.init_db();db.init_db()
  self.assertEqual(self.client.get('/api/primary-bot').status_code,200)
 def test_two_devices_cannot_both_win_selection(self):
  from concurrent.futures import ThreadPoolExecutor
  def choose(_):return self.client.patch('/api/primary-bot',json={'primary_bot_id':self.bid,'expected_version':1}).status_code
  with ThreadPoolExecutor(max_workers=2) as pool:statuses=list(pool.map(choose,range(2)))
  self.assertEqual(sorted(statuses),[200,409])
if __name__=='__main__':unittest.main()
