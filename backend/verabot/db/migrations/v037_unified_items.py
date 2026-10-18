"""v36 → v37：统一事项。reminders 增加任务关联与清单计数；新表 reminder_checklist；
回填未删除的 scheduled_tasks / 未挂周期任务的 owned_tasks 各一条事项。

迁移前备份 verabot.db.bak-before-v37-<时间戳>。列与表幂等；回填按 (user_id, task_kind, task_id)
唯一索引去重，可重复执行。
"""
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

from ._util import _add_column, _columns

CHECKLIST_SCHEMA = """
CREATE TABLE IF NOT EXISTS reminder_checklist (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reminder_id INTEGER NOT NULL REFERENCES reminders(id) ON DELETE CASCADE,
  text TEXT NOT NULL,
  done INTEGER NOT NULL DEFAULT 0,
  position INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_rcl_reminder ON reminder_checklist(user_id, reminder_id, position, id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_rem_task
  ON reminders(user_id, task_kind, task_id) WHERE task_id IS NOT NULL;
"""


def backup_before_v37() -> None:
    from ..database import DB_PATH
    path = Path(DB_PATH)
    if not path.is_file():
        return
    source = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    try:
        try:
            version = source.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()
        except sqlite3.OperationalError:
            return
        if not version or int(version[0]) >= 37:
            return
        destination = path.with_name(
            path.name + ".bak-before-v37-" + datetime.now().strftime("%Y%m%d-%H%M%S-%f")
        )
        target = sqlite3.connect(destination)
        try:
            source.backup(target)
        finally:
            target.close()
        destination.chmod(0o600)
    finally:
        source.close()


def _backfill_task_items(c) -> None:
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S+00:00")
    scheduled = c.execute(
        """SELECT id, user_id, bot_id, title, next_run_at_utc, timezone, created_at
           FROM scheduled_tasks WHERE state!='deleted'"""
    ).fetchall()
    for row in scheduled:
        tid, user_id, bot_id, title, next_run, tz, created = row
        exists = c.execute(
            "SELECT 1 FROM reminders WHERE user_id=? AND task_kind='scheduled' AND task_id=?",
            (user_id, tid),
        ).fetchone()
        if exists:
            continue
        title_text = (title or "周期任务")[:200]
        c.execute(
            """INSERT INTO reminders(
                 user_id, bot_id, content, due_at, done, created_at, title, note, timezone, due_utc,
                 all_day, rrule, occurrence_index, status, snoozed_until, priority, created_by,
                 assignee_bot_id, source_message_id, client, notify, alert_offsets, version,
                 completed_at, cancelled_at, updated_at, task_kind, task_id, source_kind,
                 checklist_done, checklist_total)
               VALUES (?,?,?,?,0,?,?,NULL,?,?,0,NULL,1,'scheduled',NULL,0,'user',?,NULL,'migration',0,'[0]',1,
                       NULL,NULL,?,?,?,'manual',0,0)""",
            (user_id, bot_id, title_text, next_run, created or now, title_text, tz or "Asia/Shanghai",
             next_run, bot_id, now, "scheduled", tid),
        )
        rid = c.execute("SELECT last_insert_rowid()").fetchone()[0]
        c.execute(
            """INSERT INTO reminder_events(user_id, reminder_id, kind, to_status, actor, client, detail, created_at)
               VALUES (?,?,'created','scheduled','system','migration',?,?)""",
            (user_id, rid, '{"migrated":true,"task_kind":"scheduled"}', now),
        )

    owned = c.execute(
        """SELECT id, user_id, owner_bot_id, goal, created_at
           FROM owned_tasks WHERE scheduled_run_id IS NULL"""
    ).fetchall()
    for row in owned:
        tid, user_id, bot_id, goal, created = row
        exists = c.execute(
            "SELECT 1 FROM reminders WHERE user_id=? AND task_kind='owned' AND task_id=?",
            (user_id, tid),
        ).fetchone()
        if exists:
            continue
        title_text = (goal or "持续任务")[:200]
        c.execute(
            """INSERT INTO reminders(
                 user_id, bot_id, content, due_at, done, created_at, title, note, timezone, due_utc,
                 all_day, rrule, occurrence_index, status, snoozed_until, priority, created_by,
                 assignee_bot_id, source_message_id, client, notify, alert_offsets, version,
                 completed_at, cancelled_at, updated_at, task_kind, task_id, source_kind,
                 checklist_done, checklist_total)
               VALUES (?,?,?,NULL,0,?,?,NULL,'Asia/Shanghai',NULL,0,NULL,1,'scheduled',NULL,0,'user',?,NULL,
                       'migration',0,'[0]',1,NULL,NULL,?,?,?,'manual',0,0)""",
            (user_id, bot_id, title_text, created or now, title_text, bot_id, now, "owned", tid),
        )
        rid = c.execute("SELECT last_insert_rowid()").fetchone()[0]
        c.execute(
            """INSERT INTO reminder_events(user_id, reminder_id, kind, to_status, actor, client, detail, created_at)
               VALUES (?,?,'created','scheduled','system','migration',?,?)""",
            (user_id, rid, '{"migrated":true,"task_kind":"owned"}', now),
        )


def migrate(c, ver: int) -> None:
    for name, ddl in (
        ("task_kind", "TEXT CHECK(task_kind IN ('scheduled','owned'))"),
        ("task_id", "INTEGER"),
        ("source_kind", "TEXT"),
        ("checklist_done", "INTEGER NOT NULL DEFAULT 0"),
        ("checklist_total", "INTEGER NOT NULL DEFAULT 0"),
    ):
        _add_column(c, "reminders", name, ddl)
    for statement in CHECKLIST_SCHEMA.split(";"):
        if statement.strip():
            c.execute(statement)
    # 回填可重复：靠唯一索引与 EXISTS 去重。列已齐后每次启动都可安全扫一遍（任务量大时仍便宜）。
    if "task_kind" in _columns(c, "reminders"):
        _backfill_task_items(c)
