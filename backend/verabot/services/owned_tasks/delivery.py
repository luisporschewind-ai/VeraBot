import json,logging
from ... import db
from ...db import owned_task_store as store
from ..notify.dispatcher import notify

def flush():
 with db.tx() as c:ids=store.pending_delivery(c)
 for sid in ids:
  try:
   with db.tx(immediate=True) as c:
    item=store.delivery_item(c,sid)
    if not item:continue
    result=json.loads(item['result_json']);mid=store.deliver_message(c,item,'任务进度：'+item['goal']+'\n\n'+result['text'])
    if mid is None:
     store.mark_delivered(c,sid,None)
     continue
    state=item['task_state']
    if state in ('completed','failed','interrupted','awaiting_user','awaiting_approval') and result.get('action') != 'consult':
     def publish_result(item=item, mid=mid, state=state, result=result):
      title={'completed':'任务已完成','failed':'任务执行失败','interrupted':'任务执行中断','awaiting_user':'任务需要你补充','awaiting_approval':'任务需要你确认'}[state]
      state_event=store.latest_state_event(c,item['task_id'],item['version'])
      note=notify(item['user_id'],category='task_result',title=item['goal'][:60]+'：'+title,body=None,bot_id=item['owner_bot_id'],message_id=mid,
       link=f"bot/{item['owner_bot_id']}/chat?message={mid}",thread_id=f"owned-task:{item['task_id']}",
       dedupe_key=f"owned-state:{state_event['id']}" if state_event else f'owned-step:{sid}',source_kind='owned_task',source_id=str(item['task_id']),source_state=state,conn=c)
      if state_event:store.mark_state_notified(c,state_event['id'],note['id'])
     if not store.notify_with_savepoint(c,publish_result):
      logging.getLogger(__name__).warning('notification delivery failed step=%s',sid)
    store.mark_delivered(c,sid,mid)
    completed=(state=='completed')
   if completed:
    from ..items.sync import on_owned_completed
    on_owned_completed(item['user_id'],item['task_id'])
  except Exception:logging.getLogger(__name__).warning('task delivery pending step=%s',sid)

 with db.tx(immediate=True) as c:
  from ...db.conversation_activity_store import generation
  for item in store.pending_state_notifications(c):
   if item.get('owner_bot_id') and generation(c,item['user_id'],'private',item['owner_bot_id'])!=item.get('delivery_generation'):
    store.mark_state_notified(c,item['id'],None)
    continue
   title={'completed':'任务已完成','failed':'任务执行失败','interrupted':'任务执行中断','awaiting_user':'任务需要你补充','awaiting_approval':'任务需要你确认'}[item['state']]
   def publish_state(item=item, title=title):
    return notify(item['user_id'],category='task_result',title=item['goal'][:60]+'：'+title,bot_id=item['owner_bot_id'],
     link=f"bot/{item['owner_bot_id']}/chat" if item['owner_bot_id'] else 'inbox',
     thread_id=f"owned-task:{item['task_id']}",dedupe_key=f"owned-state:{item['id']}",
     source_kind='owned_task',source_id=str(item['task_id']),source_state=item['state'],occurred_at=item['created_at'],conn=c)
   note=None
   def remember():
    nonlocal note
    note=publish_state()
   if store.notify_with_savepoint(c,remember) and note:
    store.mark_state_notified(c,item['id'],note['id'])
   else:
    logging.getLogger(__name__).warning('owned state notification failed event=%s',item['id'])
