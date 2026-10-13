"""Persistent notifications can be produced in any process; no memory hub required."""
from ... import db
from ...db import notification_event_store as store, reminder_store
from ..reminders import clock
from .dispatcher import _public

def list_events(user_id, *, after=None, through=None, limit=100):
    with db.tx() as c:
        c.execute('BEGIN') # all pages see a committed snapshot
        upper = store.bounds(c, user_id)
        reset = (after is not None and (after < 0 or after > upper)) or (through is not None and (through > upper or through < (after or 0)))
        base = {'events': [], 'next_cursor': upper, 'upper_bound': upper, 'has_more': False,
                'server_time': clock.iso_utc(clock.now()), 'reset_required': bool(reset)}
        if after is None or reset: return base
        bound = upper if through is None else through
        found = store.page(c, user_id, after, bound, max(1, min(limit, 200)) + 1)
        more = len(found) > max(1, min(limit, 200))
        found = found[:max(1, min(limit, 200))]
        for item in found:
            note = reminder_store.notification_for_user(c, item['notification_id'], user_id)
            base['events'].append({'event_id': item['id'], 'notification_id': item['notification_id'],
                'operation': item['operation'] if note else 'deleted', 'notification': _public(note) if note else None})
        base.update(next_cursor=found[-1]['id'] if more else bound, upper_bound=bound, has_more=more)
        return base
