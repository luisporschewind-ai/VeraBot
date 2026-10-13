import asyncio,json,time
import httpx
from ... import db
from ...db import owned_task_store as store
from ...agents.tool_router import dispatch
from ...tools.registry import ToolContext
from .. import llm
from . import policy,context

def fail(code,text,action='failed'):return {'action':action,'text':text,'blocker_code':code}
async def run_step(step):
 with db.tx() as c:task=store.live(c,step)
 if not task:return fail('stopped','任务已停止','interrupted')
 with db.tx() as c:
  if not store.consult_permitted(c,step,task):return fail('consultation_revoked','咨询权限已撤回，请重新安排','await_user')
 bot=db.get_bot(task['user_id'],step['bot_id'])
 if not bot:return fail('bot_deleted','负责 Bot 已删除')
 auth=json.loads(task['authorization_json']);tools=policy.allowed(task['user_id'],bot,auth,step['kind']=='consult')
 ctx=ToolContext(user_id=task['user_id'],bot=bot,execution_mode='owned',scheduled_authorization=auth,user_text=task['goal'])
 ctx.owned_step=step;ctx.turn.untrusted_tainted=bool(task.get('tainted'))
 messages=context.build(task,step,bot)
 for round_no in range(5):
  with db.tx() as c:
   live=store.live(c,step)
  if not live:return fail('stopped','任务已停止','interrupted')
  used,budget=db.token_budget(task['user_id'])
  if used>=budget:return fail('quota_exceeded','今日额度已用完，请稍后显式继续','await_user')
  try:
   with db.tx(immediate=True) as c:cid=store.begin_call(c,step)
  except ValueError as e:return fail('budget_or_limit',str(e),'await_user')
  started=time.monotonic();usage=None
  try:
   msg,usage=await asyncio.wait_for(llm.complete(messages,tools if round_no<4 else None,max_tokens=max(1,2048-live['chain_output'])),timeout=min(60,max(1,240-live['chain_seconds'])))
  except asyncio.CancelledError:raise
  except Exception as e:
   status=getattr(e,'status_code',None)
   transient=isinstance(e,httpx.ConnectError) or status==429 or isinstance(status,int) and status>=500
   return fail('provider_temporary' if transient else 'execution_unknown','服务暂时不可用' if transient else '请求结果不确定，请核实后继续','retry_wait' if transient and step['attempts']<3 else 'interrupted')
  finally:
   with db.tx(immediate=True) as c:store.record_call(c,cid,usage,time.monotonic()-started)
  with db.tx() as c:
   if not store.live(c,step):return fail('stopped','任务已停止','interrupted')
  with db.tx() as c:current=store.live(c,step)
  if not current:return fail('stopped','任务已停止','interrupted')
  if current['chain_output']>2048 or current['chain_seconds']>240:return fail('output_limit','本次执行达到输出或时间上限，请调整任务','await_user')
  calls=msg.get('tool_calls') or []
  if calls:
   if round_no>=4:return fail('tool_limit','工具轮次达到上限','await_user')
   messages.append({'role':'assistant','content':msg.get('content'),'tool_calls':calls})
   for call in calls:
    name=call['function']['name']
    try:
     with db.tx(immediate=True) as c:store.count_tool(c,step)
     policy.require(ctx,name)
     result=await dispatch(ctx,name,call['function'].get('arguments','{}'),call_id=call['id'])
    except ValueError as e:return fail('permission_or_limit',str(e),'await_user')
    if result.get('status')=='pending_confirmation':
     return {'action':'await_approval','text':'请确认操作：'+result.get('label',name),'action_id':result['action_id'],'tainted':ctx.turn.untrusted_tainted,'tool_history':messages[2:]}
    if result.get('error'):return fail(result.get('code','tool_failed'),'查询未完成：'+str(result['error']),'await_user')
    messages.append({'role':'tool','tool_call_id':call['id'],'content':json.dumps(result,ensure_ascii=False)[:12000]})
   continue
  if msg.get('_finish_reason')=='length':return fail('truncated','结果被截断，请调整目标','await_user')
  try:
   obj=json.loads(msg.get('content') or '')
   if not isinstance(obj,dict) or obj.get('action') not in ('completed','consult','await_user','failed') or not isinstance(obj.get('text'),str) or not obj['text'].strip():raise ValueError()
   if step['kind']=='consult' and obj['action']=='consult':raise ValueError()
   obj['tainted']=ctx.turn.untrusted_tainted
   return obj
  except (ValueError,TypeError):return fail('invalid_result','模型未给出完整任务结果','await_user')
 return fail('tool_limit','任务达到执行上限','await_user')
