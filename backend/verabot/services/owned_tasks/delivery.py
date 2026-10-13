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
    notify(item['user_id'],category='bot_message',title='任务有新进度',body=None,bot_id=item['owner_bot_id'],message_id=mid,link=f"bot/{item['owner_bot_id']}",thread_id=f"owned-task:{item['task_id']}",dedupe_key=f'owned-step:{sid}',conn=c)
    store.mark_delivered(c,sid,mid)
  except Exception:logging.getLogger(__name__).warning('task delivery pending step=%s',sid)
