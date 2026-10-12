"""Completion and inbox/message creation are one transaction."""
import json
import logging
from ... import db
from ...db import scheduled_run_store as runs, scheduled_task_store as tasks
from ..notify.dispatcher import notify
from . import clock

def deliver(c,run,now):
    if run['delivered_at'] or run['state'] in ('cancelled','skipped','retry_wait'): return
    snapshot=json.loads(run['task_snapshot_json'])
    bot_id=run['bot_id']
    mid=None
    if run['state']=='succeeded' and bot_id:
        from ...db.message_store import add_scheduled
        mid=add_scheduled(c,run['user_id'],bot_id,run['id'],
            '定时任务：'+snapshot['title']+'\n\n'+(run['result_text'] or ''),clock.iso(now))
    state_title={'succeeded':'已完成','interrupted':'执行中断','failed':'执行失败'}.get(run['state'],'执行结束')
    note=notify(run['user_id'],category='bot_message',title=snapshot['title']+'：'+state_title,
        body=None,bot_id=bot_id,message_id=mid,link=f'bot/{bot_id}' if bot_id else None,
        thread_id=f"scheduled-task:{run['task_id']}",dedupe_key=f"scheduled_task:{run['id']}",conn=c)
    runs.set_delivery(c,run['id'],mid,note['id'],now)

def complete_once(c,run):
    tasks.complete_once(c,run,clock.now())

def commit_result(run_id,lease_token,result):
    now=clock.now()
    with db.tx(immediate=True) as c:
        if not runs.finish(c,run_id,lease_token,result,now): return False
        run=runs.get(c,run_id)
        complete_once(c,run)
        if run['state']=='failed' and run['error_code'] in ('permission_revoked','bot_deleted'):
            tasks.update(c,run['user_id'],run['task_id'],dict(
                state='paused',pause_reason=run['error_code'],version=tasks.fetch(c,run['user_id'],run['task_id'])['version']+1,
                updated_at=clock.iso(now)))
    # Model result is durable even if notification creation fails.
    flush_pending()
    return True

def flush_pending():
    with db.tx() as c:
        pending=runs.pending_delivery(c)
    delivered=0
    for candidate in pending:
        try:
            with db.tx(immediate=True) as c:
                run=runs.get(c,candidate['id'])
                if not run or run['delivered_at']: continue
                deliver(c,run,clock.now())
            delivered+=1
        except Exception:
            logging.getLogger('verabot.scheduled_tasks').warning('delivery pending run=%s',candidate['id'])
    return delivered
