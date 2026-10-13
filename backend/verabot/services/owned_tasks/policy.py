"""Frozen permissions; no task creation, memory writes or recursive delegation."""
from ... import db
from ...agents.tool_router import schemas_for
from ..scheduled_tasks.policy import snapshot_tools
from ..mcp import service as mcp
from ...db import mcp_store
from ..mcp import policy as mcp_policy

def snapshot(uid,bot,goal=None):
 out=snapshot_tools(uid,bot)
 out['__delegates']=list(bot.get('delegate_to') or []) if 'ask_bot' in bot.get('allowed_tools',[]) else []
 if goal is not None:
  from ...db import owned_task_store
  with db.tx() as c:out['__memory_ids']=owned_task_store.memory_ids(c,uid,bot)
 for name in ('web_search','web_read_result'):
  if name in bot.get('allowed_tools',[]):out[name]='builtin'
 for t,server in mcp.connected_tool_rows(uid):
  if t['full_name'] in bot.get('allowed_tools',[]) and mcp_policy.requires_confirmation(t) and t.get('status')=='active' and t.get('accepted_hash') in (None,t.get('def_hash')):
   out[t['full_name']]=t['def_hash']
 return out

def allowed(uid,bot,frozen,consult=False):
 if consult:return []
 current=snapshot(uid,bot)
 names={k for k,v in frozen.items() if current.get(k)==v}
 return [t for t in schemas_for(bot,0,False,uid) if t['function']['name'] in names]
def require(ctx,name):
 from ...db import owned_task_store
 with db.tx() as c:
  if not owned_task_store.live(c,ctx.owned_step):raise ValueError("任务已停止")
 bot=db.get_bot(ctx.user_id,ctx.bot['id'])
 if not bot or name not in snapshot(ctx.user_id,bot) or snapshot(ctx.user_id,bot).get(name)!=ctx.scheduled_authorization.get(name):raise ValueError('任务权限已撤回或工具变更')
