"""Primary identity and explicit unattended-execution consent."""
from .. import db
from ..db import primary_bot_store as store
from .scheduled_tasks.contracts import TaskError

def public(s):return {k:(bool(v) if k=='active_enabled' else v) for k,v in s.items() if k!='user_id'}
def get(user_id):
 with db.tx() as c:return public(store.get(c,user_id))
def update(user_id,payload,expected_version):
 with db.tx(immediate=True) as c:
  s=store.get(c,user_id)
  if s['version']!=expected_version:raise TaskError('version_conflict','设置已更新，请刷新',409)
  if 'primary_bot_id' in payload and payload['primary_bot_id'] is not None:
   if not store.owns_bot(c,user_id,payload['primary_bot_id']):
    raise TaskError('not_found','Bot 不存在',404)
  changes=dict(payload,version=s['version']+1)
  if payload.get('primary_bot_id',s['primary_bot_id']) is None:
   if payload.get('active_enabled'):raise TaskError('no_primary_bot','请先选择主 Bot',422)
   changes['active_enabled']=False
  store.update(c,user_id,changes)
  if not payload.get('active_enabled',s['active_enabled']) or changes.get('active_enabled') is False:
   from ..db import primary_bot_store
   primary_bot_store.stop_owned_if_available(c,user_id)
  return public(store.get(c,user_id))
