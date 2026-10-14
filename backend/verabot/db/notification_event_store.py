"""Notification event feed. Caller owns read snapshot and user authorization."""
from .database import rows

def bounds(c, user_id):
    return c.execute('SELECT COALESCE(MAX(id),0) FROM notification_events WHERE user_id=?', (user_id,)).fetchone()[0]

def page(c, user_id, after, through, limit):
    return rows(c.execute('SELECT * FROM notification_events WHERE user_id=? AND id>? AND id<=? ORDER BY id LIMIT ?',
                          (user_id, after, through, limit)).fetchall())


def begin_snapshot(c):
    c.execute('BEGIN')


def current_notifications(c, user_id, ids):
    if not ids: return []
    placeholders = ','.join('?' for _ in ids)
    return rows(c.execute(f'SELECT * FROM notifications WHERE user_id=? AND id IN ({placeholders})', (user_id, *ids)).fetchall())
