"""Durable account notification changes; preserve existing FK/category contracts."""
from ._util import _add_column

def migrate(c, ver):
    _add_column(c, "push_devices", "local_events", "INTEGER NOT NULL DEFAULT 0")
    _add_column(c, "notification_prefs", "sound_enabled", "INTEGER NOT NULL DEFAULT 1")
    for name in ('kind', 'source_kind', 'source_id', 'suppression_reason'):
        _add_column(c, 'notifications', name, 'TEXT')
    c.execute('''CREATE TABLE IF NOT EXISTS notification_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        notification_id INTEGER NOT NULL, operation TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
    )''')
    c.execute('CREATE INDEX IF NOT EXISTS idx_notification_events_user ON notification_events(user_id,id)')
    for action, ref, operation in [('INSERT', 'NEW', 'created'), ('UPDATE', 'NEW', 'updated'), ('DELETE', 'OLD', 'deleted')]:
        c.execute(f'''CREATE TRIGGER IF NOT EXISTS notification_event_{action.lower()} AFTER {action} ON notifications
            BEGIN INSERT INTO notification_events(user_id,notification_id,operation)
            VALUES ({ref}.user_id,{ref}.id,'{operation}'); END''')
    # Preserve existing history as a silent bootstrap baseline.
    if ver < 30:
        c.execute("INSERT INTO notification_events(user_id,notification_id,operation) SELECT user_id,id,'updated' FROM notifications")

    c.execute("""CREATE TRIGGER IF NOT EXISTS owned_task_notification_resolved AFTER UPDATE OF state ON owned_tasks
        WHEN OLD.state != NEW.state
        BEGIN UPDATE notifications SET read_at=COALESCE(read_at,strftime('%Y-%m-%dT%H:%M:%SZ','now'))
        WHERE user_id=NEW.user_id AND source_kind='owned_task' AND source_id=CAST(NEW.id AS TEXT)
          AND read_at IS NULL; END""")
