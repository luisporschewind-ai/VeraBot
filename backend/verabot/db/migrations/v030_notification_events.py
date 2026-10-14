"""Durable account notification changes; preserve existing FK/category contracts."""
from ._util import _add_column

def migrate(c, ver):
    _add_column(c, "push_devices", "local_events", "INTEGER NOT NULL DEFAULT 0")
    _add_column(c, "notification_prefs", "sound_enabled", "INTEGER NOT NULL DEFAULT 1")
    _add_column(c, "owned_events", "notified_at", "TEXT")
    _add_column(c, "owned_events", "notification_id", "INTEGER REFERENCES notifications(id) ON DELETE SET NULL")
    for name in ('kind', 'source_kind', 'source_id', 'source_state', 'suppression_reason'):
        _add_column(c, 'notifications', name, 'TEXT')
    c.execute('''CREATE TABLE IF NOT EXISTS notification_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        notification_id INTEGER NOT NULL, operation TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
    )''')
    c.execute('CREATE INDEX IF NOT EXISTS idx_notification_events_user ON notification_events(user_id,id)')
    for action, ref, operation in [('INSERT', 'NEW', 'created'), ('UPDATE', 'NEW', 'updated'), ('DELETE', 'OLD', 'deleted')]:
        c.execute(f'DROP TRIGGER IF EXISTS notification_event_{action.lower()}')
        guard = f'WHEN EXISTS (SELECT 1 FROM users WHERE id={ref}.user_id)'
        c.execute(f'''CREATE TRIGGER notification_event_{action.lower()} AFTER {action} ON notifications
            {guard}
            BEGIN INSERT INTO notification_events(user_id,notification_id,operation)
            VALUES ({ref}.user_id,{ref}.id,'{operation}'); END''')
    if ver < 30:
        c.execute("""UPDATE owned_events SET notified_at=(SELECT n.created_at FROM notifications n
            WHERE n.user_id=owned_events.user_id AND n.dedupe_key='owned-step:' || json_extract(owned_events.payload_json,'$.step_id')),
            notification_id=(SELECT n.id FROM notifications n WHERE n.user_id=owned_events.user_id
            AND n.dedupe_key='owned-step:' || json_extract(owned_events.payload_json,'$.step_id'))""")
    # Preserve existing history as a silent bootstrap baseline.
    if ver < 30:
        c.execute("INSERT INTO notification_events(user_id,notification_id,operation) SELECT user_id,id,'updated' FROM notifications")

    c.execute("""CREATE TRIGGER IF NOT EXISTS owned_task_notification_resolved AFTER UPDATE OF state ON owned_tasks
        WHEN OLD.state != NEW.state
        BEGIN UPDATE notifications SET read_at=COALESCE(read_at,strftime('%Y-%m-%dT%H:%M:%SZ','now'))
        WHERE user_id=NEW.user_id AND source_kind='owned_task' AND source_id=CAST(NEW.id AS TEXT)
          AND read_at IS NULL; END""")
