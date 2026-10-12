"""Calendar recurrence with explicit DST round-trip validation."""
import json
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
from dateutil.rrule import rrulestr
from . import clock
from .contracts import TaskError

def validate(payload, now, *, allow_past=False):
    try:
        tz=ZoneInfo(payload['timezone'])
        start=datetime.fromisoformat(payload['start_at'].replace('Z','+00:00'))
        if start.tzinfo is None:
            raise ValueError()
        local=start.astimezone(tz)
        if start.utcoffset()!=local.utcoffset() or start.replace(tzinfo=None)!=local.replace(tzinfo=None):
            raise ValueError()
        if start<=now and not allow_past:
            raise TaskError('invalid_schedule','首次时间必须在未来')
    except TaskError:
        raise
    except (ValueError, KeyError, ZoneInfoNotFoundError):
        raise TaskError('invalid_schedule','时间或时区无效，时间必须带正确时区偏移')
    repeat=payload.get('repeat','once')
    weekdays=payload.get('weekdays') or []
    if repeat not in ('once','daily','weekdays','weekly'):
        raise TaskError('invalid_schedule','不支持的重复规则')
    if repeat=='weekly' and (not weekdays or len(set(weekdays))!=len(weekdays) or any(type(x)!=int or x not in range(7) for x in weekdays)):
        raise TaskError('invalid_schedule','每周规则需要不重复的星期（0–6）')
    if repeat!='weekly' and weekdays:
        raise TaskError('invalid_schedule','只有每周规则可指定星期')
    days=('MO','TU','WE','TH','FR','SA','SU')
    rule=None
    if repeat=='daily': rule='FREQ=DAILY'
    if repeat=='weekdays': rule='FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR'
    if repeat=='weekly': rule='FREQ=WEEKLY;BYDAY='+','.join(days[x] for x in sorted(weekdays))
    task={'start_at_utc':clock.iso(start),'timezone':tz.key,'rrule':rule}
    first=next_after(task, now)
    if first is None:
        raise TaskError('invalid_schedule','一次性排程需要提供未来的首次时间')
    return dict(task,next_run_at_utc=clock.iso(first),repeat=repeat,weekdays_json=json.dumps(sorted(weekdays)))

def occurrences(task):
    tz=ZoneInfo(task['timezone'])
    start=clock.parse(task['start_at_utc']).astimezone(tz).replace(tzinfo=None)
    if not task.get('rrule'):
        yield clock.parse(task['start_at_utc'])
        return
    rule=rrulestr(task['rrule'],dtstart=start)
    for naive in rule:
        local=naive.replace(tzinfo=tz,fold=0)
        utc=local.astimezone(timezone.utc)
        if utc.astimezone(tz).replace(tzinfo=None)!=naive:
            continue
        yield utc

def next_after(task, after):
    for value in occurrences(task):
        if value>after:
            return value
    return None

def latest_due(task, now):
    latest=None
    for value in occurrences(task):
        if value>now: break
        latest=value
    return latest
