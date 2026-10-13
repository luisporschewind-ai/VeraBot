"""Due-time scans enqueue work; they never call a model."""
import logging
from datetime import timedelta
from ... import db
from ...db import scheduled_task_store as tasks, scheduled_run_store as runs
from . import clock, schedule

log=logging.getLogger('verabot.scheduled_tasks')

def tick(now=None):
    now=now or clock.now()
    stats={'enqueued':0,'skipped':0,'completed':0}
    with db.tx() as c:
        ids=[t['id'] for t in tasks.due(c,clock.iso(now))]
    for tid in ids:
        try:
            _process(tid,now,stats)
        except Exception:
            log.exception("task scheduling failed id=%s",tid)
    return stats

def _process(tid,now,stats):
    with db.tx(immediate=True) as c:
        # Internal scheduler is the only cross-tenant accessor.
        owner=tasks.owner(c,tid)
        if owner is None: return
        t=tasks.fetch(c,owner,tid)
        if t['state']!='active': return
        if not t['bot_id']:
            runs.cancel_pending(c,tid,now,include_running=True)
            tasks.update(c,t['user_id'],tid,dict(state='paused',pause_reason='bot_deleted',
                version=t['version']+1,updated_at=clock.iso(now)))
            return
        if not t['next_run_at_utc']: return
        due=clock.parse(t['next_run_at_utc'])
        if due>now: return
        when=due
        error=None
        if runs.active(c,tid):
            error='previous_run_active'
        elif now-due>timedelta(minutes=10):
            if t['misfire_policy']=='latest':
                when=schedule.latest_due(t,now) or due
                if now-when>timedelta(hours=24): error='missed'
            else: error='missed'
        if not runs.occurrence_exists(c,tid,t['schedule_revision'],when):
            rid=runs.insert(c,t,when,now,state='skipped' if error else 'queued',error=error)
            if not error and t.get('execution_mode')=='owned':
                from ..owned_tasks.schedules import enqueue_occurrence
                enqueue_occurrence(c,t,rid)
            stats['skipped' if error else 'enqueued']+=1
        high_water=runs.high_water(c,tid,t['schedule_revision'])
        after=max(now,high_water) if high_water else now
        nxt=schedule.next_after(t,after)
        values=dict(next_run_at_utc=clock.iso(nxt) if nxt else None,updated_at=clock.iso(now))
        if nxt is None and error:
            values['state']='completed'; stats['completed']+=1
        tasks.update(c,t['user_id'],tid,values)
