from ... import db
from ...db import owned_task_store as store

def preflight(uid,aid):
 with db.tx() as c:
  a=store.task_action(c,uid,aid)
  if a and a.get('owned_task_id') and not store.action_current(c,a):raise ValueError('任务已停止、版本已更新或尚未进入确认状态')
def _content(a):
 from ..actions import _decrypt
 decoded=_decrypt(a.get("owned_result_enc"))
 return decoded.get("content") if decoded else None

def resolve(uid,aid):
 with db.tx(immediate=True) as c:
  a=store.task_action(c,uid,aid)
  if a and a.get('owned_task_id'):store.resolve_action(c,a,_content(a))
def reconcile():
 with db.tx(immediate=True) as c:
  store.expire_actions(c)
  for a in store.unresolved_actions(c):store.resolve_action(c,a,_content(a))
