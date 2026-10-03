"""v10 → v11：提醒补列（状态、时区、重复、归属）并回填；reminder_events / notifications /
notification_deliveries / notification_prefs / push_devices / idempotency_keys。迁移前备份（backup_before_v11）。"""
import json
import sqlite3
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

from ...core.config import DB_PATH, TIMEZONE
from ..database import now_iso
from ._util import _add_column

# v11：提醒状态机 + 通用通知层。推送相关表一次建好，之后的分期只加代码。
REMINDER_SCHEMA = """
CREATE TABLE IF NOT EXISTS reminder_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reminder_id INTEGER NOT NULL REFERENCES reminders(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  from_status TEXT, to_status TEXT,
  occurrence_due_utc TEXT,
  actor TEXT NOT NULL,
  actor_bot_id INTEGER,
  client TEXT,
  detail TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_rev_rem ON reminder_events(user_id, reminder_id, id);
CREATE TABLE IF NOT EXISTS notifications (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  category TEXT NOT NULL CHECK (category IN ('reminder','bot_message','delegation','plugin','system')),
  title TEXT NOT NULL, body TEXT, sensitive INTEGER NOT NULL DEFAULT 0,
  bot_id INTEGER REFERENCES bots(id) ON DELETE SET NULL,
  reminder_id INTEGER REFERENCES reminders(id) ON DELETE SET NULL,
  message_id INTEGER REFERENCES messages(id) ON DELETE SET NULL,
  plugin_id TEXT, link TEXT, thread_id TEXT,
  dedupe_key TEXT NOT NULL,
  created_at TEXT NOT NULL, read_at TEXT, opened_at TEXT, expires_at TEXT,
  UNIQUE(user_id, dedupe_key)
);
CREATE INDEX IF NOT EXISTS idx_ntf_user ON notifications(user_id, read_at, id);
CREATE TABLE IF NOT EXISTS notification_deliveries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  notification_id INTEGER NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  channel TEXT NOT NULL CHECK (channel IN ('inbox','local','apns')),
  device_id TEXT,
  state TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT, apns_id TEXT,
  scheduled_for TEXT, sent_at TEXT, delivered_at TEXT, opened_at TEXT, updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_ndl_state ON notification_deliveries(state, scheduled_for);
CREATE TABLE IF NOT EXISTS notification_prefs (
  user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  enabled INTEGER NOT NULL DEFAULT 1,
  categories TEXT NOT NULL DEFAULT '{}',
  muted_bots TEXT NOT NULL DEFAULT '[]',
  quiet_enabled INTEGER NOT NULL DEFAULT 0,
  quiet_start TEXT NOT NULL DEFAULT '23:00', quiet_end TEXT NOT NULL DEFAULT '08:00',
  quiet_timezone TEXT NOT NULL DEFAULT 'Asia/Shanghai',
  preview TEXT NOT NULL DEFAULT 'title',
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS push_devices (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL,
  platform TEXT NOT NULL DEFAULT 'ios',
  apns_token TEXT,
  apns_env TEXT,
  app_version TEXT, os_version TEXT, timezone TEXT,
  local_reminders INTEGER NOT NULL DEFAULT 1,
  disabled_at TEXT, last_seen_at TEXT NOT NULL, created_at TEXT NOT NULL,
  UNIQUE(user_id, device_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_push_token ON push_devices(apns_token) WHERE apns_token IS NOT NULL;
CREATE TABLE IF NOT EXISTS idempotency_keys (
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  key TEXT NOT NULL,
  status_code INTEGER NOT NULL,
  body TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (user_id, key)
);
CREATE INDEX IF NOT EXISTS idx_rem_user_status ON reminders(user_id, status, due_utc);
CREATE INDEX IF NOT EXISTS idx_rem_assignee ON reminders(user_id, assignee_bot_id);
"""


def _backup_before_v11() -> None:
    """已有库升到 v11 之前复制一份。新文件还没有 schema_meta 时不备份。"""
    path = Path(DB_PATH)
    if not path.is_file():
        return
    try:
        src = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    except sqlite3.Error:
        return
    try:
        row = src.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()
    except sqlite3.Error:
        return
    finally:
        src.close()
    if not row or int(row[0]) >= 11:
        return
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    dest = path.with_name(f"{path.name}.bak-before-v11-{stamp}")
    if dest.exists():
        dest = path.with_name(f"{path.name}.bak-before-v11-{stamp}-{datetime.now().microsecond}")
    src = sqlite3.connect(path)
    dst = sqlite3.connect(dest)
    try:
        src.backup(dst)
    finally:
        dst.close()
        src.close()


def _legacy_due(text: str | None):
    if text is None or not str(text).strip():
        return None
    raw = str(text).strip().replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(raw)
    except ValueError:
        return "invalid"
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=ZoneInfo(TIMEZONE))
    return parsed


def _backfill_reminders(c, now: datetime) -> None:
    rows = c.execute("SELECT id, user_id, bot_id, content, due_at, done, created_at FROM reminders").fetchall()
    for row in rows:
        content = row[3] or ""
        title = content[:200]
        note = content[200:] or None
        parsed = _legacy_due(row[4])
        due_at = due_utc = None
        if parsed == "invalid":
            extra = f"原时间：{row[4]}"
            note = f"{note}\n{extra}" if note else extra
        elif parsed is not None:
            local = parsed.astimezone(ZoneInfo(TIMEZONE)).replace(second=0, microsecond=0)
            due_at = local.isoformat(timespec="minutes")
            due_utc = local.astimezone(timezone.utc).isoformat(timespec="seconds")
        if row[5]:
            status, completed = "done", None
        elif parsed is None or parsed == "invalid":
            status, completed = "scheduled", None
        elif parsed > now:
            status, completed = "scheduled", None
        elif now - parsed <= timedelta(hours=24):
            status, completed = "due", None
        else:
            status, completed = "missed", None
        c.execute(
            """UPDATE reminders SET title=?, note=?, content=?, due_at=?, due_utc=?, timezone=?, all_day=0,
               occurrence_index=1, status=?, priority=0, created_by='bot', assignee_bot_id=?,
               notify=?, alert_offsets='[0]', version=1, completed_at=?, updated_at=?, done=?
               WHERE id=?""",
            (title, note, title, due_at, due_utc, TIMEZONE, status, row[2],
             0 if due_at is None else 1, completed, row[6], 1 if status == "done" else 0, row[0]),
        )
        c.execute(
            """INSERT INTO reminder_events(user_id, reminder_id, kind, to_status, actor, client, detail, created_at)
               VALUES (?,?, 'created', ?, 'system', 'scheduler', ?, ?)""",
            (row[1], row[0], status, json.dumps({"migrated": True}, ensure_ascii=False), row[6] or now_iso()),
        )


def migrate(c, ver: int) -> None:
    # --- v11：提醒状态机与通知层。列和表每次都补；回填只在第一次从旧版本升上来时做 ---
    for name, ddl in (
        ("title", "TEXT"),
        ("note", "TEXT"),
        ("timezone", "TEXT NOT NULL DEFAULT 'Asia/Shanghai'"),
        ("due_utc", "TEXT"),
        ("all_day", "INTEGER NOT NULL DEFAULT 0"),
        ("rrule", "TEXT"),
        ("occurrence_index", "INTEGER NOT NULL DEFAULT 1"),
        ("status", "TEXT NOT NULL DEFAULT 'scheduled'"),
        ("snoozed_until", "TEXT"),
        ("priority", "INTEGER NOT NULL DEFAULT 0"),
        ("created_by", "TEXT NOT NULL DEFAULT 'user'"),
        ("assignee_bot_id", "INTEGER"),
        ("source_message_id", "INTEGER"),
        ("client", "TEXT"),
        ("notify", "INTEGER NOT NULL DEFAULT 1"),
        ("alert_offsets", "TEXT NOT NULL DEFAULT '[0]'"),
        ("version", "INTEGER NOT NULL DEFAULT 1"),
        ("completed_at", "TEXT"),
        ("cancelled_at", "TEXT"),
        ("updated_at", "TEXT"),
    ):
        _add_column(c, "reminders", name, ddl)
    c.executescript(REMINDER_SCHEMA)
    # v10 旧表没有 bot_id 外键，只靠 ON DELETE SET NULL 覆盖不了已有库。每次启动重建触发器。
    c.execute("DROP TRIGGER IF EXISTS reminders_clear_assignee")
    c.execute("""CREATE TRIGGER reminders_clear_assignee
            AFTER DELETE ON bots
            FOR EACH ROW
            BEGIN
              UPDATE reminders SET bot_id=NULL WHERE bot_id=OLD.id;
              UPDATE reminders SET assignee_bot_id=NULL WHERE assignee_bot_id=OLD.id;
            END""")
    c.execute("""CREATE TRIGGER IF NOT EXISTS reminders_clear_message
            AFTER DELETE ON messages
            FOR EACH ROW
            BEGIN
              UPDATE reminders SET source_message_id=NULL WHERE source_message_id=OLD.id;
            END""")
    if ver < 11:
        _backfill_reminders(c, datetime.now(timezone.utc))
