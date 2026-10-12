"""Persistent queue and lease SQL. Network work never holds these transactions."""
import json
from datetime import timedelta
from uuid import uuid4
from .database import row, rows
from ..services.scheduled_tasks import clock

def fetch(c, user_id, task_id, run_id):
    return row(c.execute("SELECT * FROM scheduled_task_runs WHERE user_id=? AND task_id=? AND id=?", (user_id,task_id,run_id)).fetchone())

def get(c, run_id):
    return row(c.execute("SELECT * FROM scheduled_task_runs WHERE id=?", (run_id,)).fetchone())

def active(c, task_id):
    return row(c.execute("SELECT * FROM scheduled_task_runs WHERE task_id=? AND state IN ('queued','running','retry_wait')", (task_id,)).fetchone())

def by_key(c, user_id, task_id, key):
    return row(c.execute("SELECT * FROM scheduled_task_runs WHERE user_id=? AND task_id=? AND idempotency_key=?", (user_id,task_id,key)).fetchone())

def insert(c, task, when, now, *, trigger='scheduled', state='queued', key=None, error=None):
    snapshot={k:task[k] for k in ('title','instruction','timezone','authorized_tools_json','schedule_revision')}
    return c.execute("""INSERT INTO scheduled_task_runs(task_id,user_id,bot_id,trigger,scheduled_for_utc,
     schedule_revision,idempotency_key,state,task_snapshot_json,available_at,created_at,error_code,finished_at)
     VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)""",
     (task['id'],task['user_id'],task['bot_id'],trigger,clock.iso(when),task['schedule_revision'],key,state,
      json.dumps(snapshot,ensure_ascii=False),clock.iso(now),clock.iso(now),error,clock.iso(now) if state=='skipped' else None)).lastrowid

def cancel_pending(c, task_id, now, *, include_running=False):
    c.execute("UPDATE scheduled_task_runs SET state='cancelled',cancel_requested=1,finished_at=? WHERE task_id=? AND state IN ('queued','retry_wait')", (clock.iso(now),task_id))
    if include_running:
        c.execute("UPDATE scheduled_task_runs SET cancel_requested=1 WHERE task_id=? AND state='running'", (task_id,))

def list_runs(c, user_id, task_id, before_id=None, limit=20):
    sql="SELECT * FROM scheduled_task_runs WHERE user_id=? AND task_id=?"
    args=[user_id,task_id]
    if before_id is not None:
        sql+=" AND id<?"; args.append(before_id)
    return rows(c.execute(sql+" ORDER BY id DESC LIMIT ?", (*args,limit)).fetchall())

def attempts(c, run_id):
    return rows(c.execute("SELECT * FROM scheduled_task_attempts WHERE run_id=? ORDER BY attempt_number",(run_id,)).fetchall())

def claim_next(c, owner, now):
    job=row(c.execute("""SELECT r.* FROM scheduled_task_runs r JOIN scheduled_tasks t ON t.id=r.task_id
      WHERE r.state IN ('queued','retry_wait') AND r.available_at<=? AND r.cancel_requested=0
      AND t.state!='deleted' AND (t.state='active' OR r.trigger='manual')
      ORDER BY r.available_at,r.id LIMIT 1""",(clock.iso(now),)).fetchone())
    if not job:
        return None
    token=uuid4().hex
    c.execute("""UPDATE scheduled_task_runs SET state='running',lease_owner=?,lease_token=?,lease_expires_at=?,
     attempt_count=attempt_count+1,started_at=COALESCE(started_at,?) WHERE id=? AND state IN ('queued','retry_wait')""",
     (owner,token,clock.iso(now+timedelta(seconds=90)),clock.iso(now),job['id']))
    job=get(c,job['id'])
    c.execute("INSERT INTO scheduled_task_attempts(run_id,attempt_number,started_at) VALUES(?,?,?)",(job['id'],job['attempt_count'],clock.iso(now)))
    return job

def live(c, run_id, token, now):
    return row(c.execute("SELECT * FROM scheduled_task_runs WHERE id=? AND lease_token=? AND state='running' AND lease_expires_at>? AND cancel_requested=0",(run_id,token,clock.iso(now))).fetchone())

def renew(c, run_id, lease_token, now):
    return c.execute("""UPDATE scheduled_task_runs SET lease_expires_at=? WHERE id=? AND lease_token=?
     AND state='running' AND lease_expires_at>? AND cancel_requested=0""",
     (clock.iso(now+timedelta(seconds=90)),run_id,lease_token,clock.iso(now))).rowcount == 1

def expired(c, now):
    return rows(c.execute("SELECT * FROM scheduled_task_runs WHERE state='running' AND lease_expires_at<=?",(clock.iso(now),)).fetchall())

def account_usage(c, run, usage, now):
    if usage:
        c.execute("""INSERT INTO usage_log(user_id,bot_id,kind,prompt_tokens,completion_tokens,total_tokens,created_at)
        SELECT ?,?,'scheduled_task',?,?,?,? WHERE EXISTS(SELECT 1 FROM users WHERE id=?)""",
        (run['user_id'],run['bot_id'],int(usage.get('prompt_tokens') or 0),int(usage.get('completion_tokens') or 0),
         int(usage.get('total_tokens') or 0),clock.iso(now),run['user_id']))

def record_usage(c, run_id, token, usage, now):
    if not usage:
        return True
    run=get(c,run_id)
    if not run or run['lease_token']!=token:
        return False
    previous=c.execute("SELECT usage_json FROM scheduled_task_attempts WHERE run_id=? AND attempt_number=?",
                       (run_id,run['attempt_count'])).fetchone()
    if not previous:
        return False
    before=json.loads(previous[0] or '{}')
    delta={k:max(0,int(v)-int(before.get(k) or 0)) for k,v in usage.items() if k in ('prompt_tokens','completion_tokens','total_tokens')}
    # If a provider reports both token components but omits total_tokens, charge
    # the reported lower bound while keeping the attempt marked usage_unknown.
    if 'total_tokens' not in delta and ('prompt_tokens' in delta or 'completion_tokens' in delta):
        delta['total_tokens']=delta.get('prompt_tokens',0)+delta.get('completion_tokens',0)
    account_usage(c,run,delta,now)
    c.execute("UPDATE scheduled_task_attempts SET usage_json=? WHERE run_id=? AND attempt_number=?",(json.dumps(usage),run_id,run['attempt_count']))
    return True

def finish(c, run_id, lease_token, result, now):
    run=get(c,run_id)
    if not run or run['state']!='running' or run['lease_token']!=lease_token or clock.parse(run['lease_expires_at'])<=now:
        return False
    state='cancelled' if run['cancel_requested'] else result.state
    c.execute("""UPDATE scheduled_task_runs SET state=?,result_text=?,error_code=?,error_summary=?,finished_at=?,
      lease_expires_at=NULL WHERE id=?""",(state,result.text,result.error_code,result.error_summary,clock.iso(now),run_id))
    record_usage(c,run_id,lease_token,result.usage,now)
    c.execute("""UPDATE scheduled_task_attempts SET state=?,finished_at=?,usage_unknown=?,error_code=?,trace_summary_json=?
     WHERE run_id=? AND attempt_number=?""",(state,clock.iso(now),int(result.usage_unknown),result.error_code,
      json.dumps(result.trace_summary),run_id,run['attempt_count']))
    return True

def set_delivery(c,run_id,message_id,notification_id,now):
    c.execute('UPDATE scheduled_task_runs SET message_id=?,notification_id=?,delivered_at=? WHERE id=?',
      (message_id,notification_id,clock.iso(now),run_id))

def interrupt(c,run,now):
    state='cancelled' if run['cancel_requested'] else 'interrupted'
    code='cancelled' if run['cancel_requested'] else 'run_interrupted'
    summary='任务已取消' if run['cancel_requested'] else '执行中断，请手动重试'
    c.execute("""UPDATE scheduled_task_runs SET state=?,error_code=?,
     error_summary=?,finished_at=?,lease_expires_at=NULL WHERE id=? AND state='running'""",
     (state,code,summary,clock.iso(now),run['id']))
    c.execute("""UPDATE scheduled_task_attempts SET state=?,finished_at=?,usage_unknown=1,error_code=?
      WHERE run_id=? AND attempt_number=? AND state='running'""",
      (state,clock.iso(now),code,run['id'],run['attempt_count']))

def requeue(c,run_id,available_at):
    c.execute("""UPDATE scheduled_task_runs SET state='retry_wait',finished_at=NULL,available_at=?,
      lease_owner=NULL,lease_token=NULL WHERE id=?""",(clock.iso(available_at),run_id))

def pending_delivery(c,limit=100):
    return rows(c.execute("""SELECT * FROM scheduled_task_runs WHERE delivered_at IS NULL
      AND state IN ('succeeded','failed','interrupted') ORDER BY id LIMIT ?""",(limit,)).fetchall())

def high_water(c,task_id,revision):
    value=c.execute("""SELECT MAX(scheduled_for_utc) FROM scheduled_task_runs
      WHERE task_id=? AND schedule_revision=? AND trigger='scheduled'""",(task_id,revision)).fetchone()[0]
    return clock.parse(value) if value else None

def occurrence_exists(c,task_id,revision,when):
    return c.execute("""SELECT 1 FROM scheduled_task_runs WHERE task_id=? AND schedule_revision=?
       AND scheduled_for_utc=? AND trigger='scheduled'""",(task_id,revision,clock.iso(when))).fetchone() is not None
