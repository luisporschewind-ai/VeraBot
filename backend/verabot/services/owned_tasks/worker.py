import asyncio
from ... import db
from ...db import owned_task_store as store
from . import executor,delivery
async def process_one(owner):
 from . import approvals
 approvals.reconcile()
 with db.tx(immediate=True) as c:
  store.fence_schedules(c);store.finish_schedules(c)
  step=store.claim_next(c,owner,db.now_iso())
 delivery.flush()
 if not step:return False
 running=asyncio.create_task(executor.run_step(step))
 async def maintain():
  count=0
  while not running.done():
   await asyncio.sleep(1);count+=1
   with db.tx(immediate=True) as c:
    valid=store.live(c,step)
    if valid and count%15==0:store.renew(c,step)
   if not valid:running.cancel();return
 monitor=asyncio.create_task(maintain())
 try:
  result=await running
 except asyncio.CancelledError:
  if asyncio.current_task().cancelling():raise
  result=executor.fail('stopped','任务已停止','interrupted')
 except Exception:
  result=executor.fail('execution_unknown','执行异常，请核实后继续','interrupted')
 finally:
  monitor.cancel();await asyncio.gather(monitor,return_exceptions=True)
 with db.tx(immediate=True) as c:
  try:store.commit_step(c,step,result)
  except ValueError as e:store.commit_step(c,step,executor.fail('invalid_action',str(e),'await_user'))
 with db.tx(immediate=True) as c:store.finish_schedules(c)
 delivery.flush();return True
