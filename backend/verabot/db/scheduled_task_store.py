"""Task SQL. All user-facing access is scoped; caller owns transaction."""
from .database import row, rows

def fetch(c, user_id, task_id):
    return row(c.execute("SELECT * FROM scheduled_tasks WHERE user_id=? AND id=?", (user_id,task_id)).fetchone())

def by_key(c, user_id, key):
    return row(c.execute("SELECT * FROM scheduled_tasks WHERE user_id=? AND idempotency_key=?", (user_id,key)).fetchone())

def list_tasks(c, user_id, *, state=None, bot_id=None, before_id=None, limit=20):
    sql="SELECT * FROM scheduled_tasks WHERE user_id=? AND state!='deleted'"
    args=[user_id]
    for col, value in (('state',state),('bot_id',bot_id)):
        if value is not None:
            sql+=f" AND {col}=?"; args.append(value)
    if before_id is not None:
        sql+=" AND id<?"; args.append(before_id)
    return rows(c.execute(sql+" ORDER BY id DESC LIMIT ?", (*args,limit)).fetchall())

def insert(c, values):
    keys=list(values)
    return c.execute(f"INSERT INTO scheduled_tasks({','.join(keys)}) VALUES({','.join('?' for _ in keys)})", tuple(values[k] for k in keys)).lastrowid

def update(c, user_id, task_id, values):
    keys=list(values)
    c.execute(f"UPDATE scheduled_tasks SET {','.join(k+'=?' for k in keys)} WHERE user_id=? AND id=?", (*[values[k] for k in keys],user_id,task_id))

def due(c, now):
    return rows(c.execute("SELECT * FROM scheduled_tasks WHERE state='active' AND (next_run_at_utc<=? OR bot_id IS NULL)",(now,)).fetchall())

def owner(c, task_id):
    found=c.execute('SELECT user_id FROM scheduled_tasks WHERE id=?',(task_id,)).fetchone()
    return found[0] if found else None

def bot_exists(c, user_id, bot_id):
    return c.execute('SELECT 1 FROM bots WHERE user_id=? AND id=?',(user_id,bot_id)).fetchone() is not None

def user_exists(c, user_id):
    return c.execute('SELECT 1 FROM users WHERE id=?',(user_id,)).fetchone() is not None

def complete_once(c, run, now):
    c.execute("""UPDATE scheduled_tasks SET state='completed',updated_at=? WHERE id=? AND state='active'
      AND rrule IS NULL AND next_run_at_utc IS NULL AND schedule_revision=?""",
      (clock_iso(now),run['task_id'],run['schedule_revision']))

def clock_iso(now):
    from ..services.scheduled_tasks.clock import iso
    return iso(now)

def schema_version(c):
    found=c.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()
    return int(found[0]) if found else 0
