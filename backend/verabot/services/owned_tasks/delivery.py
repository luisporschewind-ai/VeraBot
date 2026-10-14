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
    state=item['task_state']
    if state in ('completed','failed','interrupted','awaiting_user','awaiting_approval') and result['action'] != 'consult':
     title={'completed':'任务已完成','failed':'任务执行失败','interrupted':'任务执行中断','awaiting_user':'任务需要你补充','awaiting_approval':'任务需要你确认'}[state]
     state_event=store.latest_state_event(c,item['task_id'],item['version'])
     note=notify(item['user_id'],category='task_result',title=item['goal'][:60]+'：'+title,body=None,bot_id=item['owner_bot_id'],message_id=mid,
      link=f"bot/{item['owner_bot_id']}/chat?message={mid}",thread_id=f"owned-task:{item['task_id']}",
      dedupe_key=f"owned-state:{state_event['id']}" if state_event else f'owned-step:{sid}',source_kind='owned_task',source_id=str(item['task_id']),source_state=state,conn=c)
     if state_event:store.mark_state_notified(c,state_event['id'],note['id'])
    store.mark_delivered(c,sid,mid)
  except Exception:logging.getLogger(__name__).warning('task delivery pending step=%s',sid)

 with db.tx(immediate=True) as c:
  for item in store.pending_state_notifications(c):
   title={'completed':'任务已完成','failed':'任务执行失败','interrupted':'任务执行中断','awaiting_user':'任务需要你补充','awaiting_approval':'任务需要你确认'}[item['state']]
   note=notify(item['user_id'],category='task_result',title=item['goal'][:60]+'：'+title,bot_id=item['owner_bot_id'],
    link=f"bot/{item['owner_bot_id']}/chat" if item['owner_bot_id'] else 'inbox',
    thread_id=f"owned-task:{item['task_id']}",dedupe_key=f"owned-state:{item['id']}",
    source_kind='owned_task',source_id=str(item['task_id']),source_state=item['state'],occurred_at=item['created_at'],conn=c)
   store.mark_state_notified(c,item['id'],note['id'])
