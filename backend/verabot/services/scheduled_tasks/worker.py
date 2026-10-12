"""Single serial worker with fenced leases and conservative interruption recovery."""
import asyncio
import logging
from datetime import timedelta
from ... import db
from ...db import scheduled_run_store as runs
from . import clock, delivery, executor
from .contracts import ExecutionResult

log=logging.getLogger('verabot.scheduled_tasks')
RETRYABLE={'provider_temporary'}

def recover_expired(now=None):
    now=now or clock.now()
    with db.tx(immediate=True) as c:
        jobs=runs.expired(c,now)
        for run in jobs:
            runs.interrupt(c,run,now)
            delivery.complete_once(c,run)
    delivery.flush_pending()
    return len(jobs)

def should_stop(run):
    with db.tx() as c:
        current=runs.get(c,run['id'])
        return not current or not runs.live(c,run['id'],run['lease_token'],clock.now())

async def _maintain(run,task):
    while not task.done():
        await asyncio.sleep(1)
        if should_stop(run):
            task.cancel()
            return
        if (clock.now()-clock.parse(run['lease_expires_at'])+timedelta(seconds=90)).total_seconds()>=15:
            with db.tx(immediate=True) as c:
                renewed=runs.renew(c,run['id'],run['lease_token'],clock.now())
            if not renewed:
                task.cancel(); return
            run['lease_expires_at']=clock.iso(clock.now()+timedelta(seconds=90))

async def process_one(owner):
    recover_expired()
    delivery.flush_pending()
    with db.tx(immediate=True) as c:
        run=runs.claim_next(c,owner,clock.now())
    if not run: return False
    task=asyncio.create_task(executor.run_scheduled(run))
    monitor=asyncio.create_task(_maintain(run,task))
    stopping=False
    try:
        result=await asyncio.wait_for(task,timeout=180)
    except TimeoutError:
        result=ExecutionResult('failed',error_code='run_timeout',error_summary='任务执行超时',usage_unknown=True)
    except asyncio.CancelledError:
        stopping=bool(asyncio.current_task().cancelling())
        result=ExecutionResult('interrupted' if stopping else 'cancelled',error_code='run_interrupted' if stopping else 'cancelled',
            error_summary='执行中断，请手动重试' if stopping else '任务已取消',usage_unknown=True)
    except Exception:
        log.exception('worker attempt failed run=%s',run['id'])
        result=ExecutionResult('failed',error_code='execution_failed',error_summary='任务执行失败',usage_unknown=True)
    finally:
        monitor.cancel()
        await asyncio.gather(monitor,return_exceptions=True)
    if result.error_code in RETRYABLE and run['attempt_count']<3:
        with db.tx(immediate=True) as c:
            if runs.finish(c,run['id'],run['lease_token'],result,clock.now()):
                current=runs.get(c,run['id'])
                if current['state']!='cancelled':
                    delay=(30,120)[run['attempt_count']-1]
                    runs.requeue(c,run['id'],clock.now()+timedelta(seconds=delay))
    else:
        # Delivery failures leave running for lease expiry. They never re-run the model.
        delivery.commit_result(run['id'],run['lease_token'],result)
    if stopping: raise asyncio.CancelledError()
    return True
