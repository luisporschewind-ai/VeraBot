import json
from ... import db
from ...db import owned_task_store as store
from ..scheduled_tasks.service import digest
from .policy import snapshot

def enqueue_occurrence(c,task,run_id):
 bot=db.get_bot(task['user_id'],task['bot_id'])
 if not bot:return None
 p={'goal':task['instruction'],'completion_criteria':'交付完整任务结果','token_limit':20000}
 # A periodic instance is authorized by the definition's original frozen tool ceiling.
 frozen=json.loads(task['authorized_tools_json']);current=snapshot(task['user_id'],bot)
 auth={k:v for k,v in current.items() if frozen.get(k)==v}
 t=store.create(c,task['user_id'],bot,p,f"scheduled-run:{run_id}",digest(p),auth)
 store.link_schedule(c,t['id'],run_id);return t['id']
