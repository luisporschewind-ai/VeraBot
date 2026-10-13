"""Settings SQL, using caller transactions."""
def get(c,user_id):
 r=c.execute('SELECT * FROM primary_bot_settings WHERE user_id=?',(user_id,)).fetchone()
 return dict(r) if r else dict(user_id=user_id,primary_bot_id=None,active_enabled=0,daily_token_limit=20000,version=1)
def update(c,user_id,fields):
 c.execute('INSERT OR IGNORE INTO primary_bot_settings(user_id) VALUES (?)',(user_id,))
 c.execute('UPDATE primary_bot_settings SET '+','.join(k+'=?' for k in fields)+' WHERE user_id=?',(*fields.values(),user_id))
def clear_bot(c,user_id,bot_id):
 c.execute('UPDATE primary_bot_settings SET primary_bot_id=NULL, active_enabled=0, version=version+1 WHERE user_id=? AND primary_bot_id=?',(user_id,bot_id))
def owns_bot(c,user_id,bot_id):
 return bool(c.execute('SELECT 1 FROM bots WHERE id=? AND user_id=?',(bot_id,user_id)).fetchone())
def stop_owned_if_available(c,user_id):
 # The business-task migration is installed in the next independently testable phase.
 if c.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='owned_tasks'").fetchone():
  from . import owned_task_store
  owned_task_store.disable_user(c,user_id)
