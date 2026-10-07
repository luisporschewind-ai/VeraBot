"""提醒、收件箱、投递、通知偏好、设备与调度查询。

业务规则留在 services / api。这里只放 SQL，调用方传入同一条连接以保持事务。
"""
from __future__ import annotations

from .database import row, rows, tx


def bot_name(conn, user_id: int, bot_id) -> str | None:
    if not bot_id:
        return None
    found = conn.execute("SELECT name FROM bots WHERE id=? AND user_id=?", (bot_id, user_id)).fetchone()
    return found[0] if found else None


def bot_exists(conn, user_id: int, bot_id) -> bool:
    return conn.execute("SELECT 1 FROM bots WHERE id=? AND user_id=?", (bot_id, user_id)).fetchone() is not None


def message_exists(conn, user_id: int, message_id) -> bool:
    return conn.execute(
        "SELECT 1 FROM messages WHERE id=? AND user_id=?", (message_id, user_id)
    ).fetchone() is not None


def fetch_reminder(conn, user_id: int, rid: int):
    return row(conn.execute("SELECT * FROM reminders WHERE id=? AND user_id=?", (rid, user_id)).fetchone())


def fetch_reminder_by_id(conn, rid: int):
    return row(conn.execute("SELECT * FROM reminders WHERE id=?", (rid,)).fetchone())


def bot_names(conn, user_id: int, ids) -> dict:
    clean = []
    for item in ids:
        if item is not None and item not in clean:
            clean.append(item)
    if not clean:
        return {}
    marks = ",".join("?" * len(clean))
    found = conn.execute(
        f"SELECT id, name FROM bots WHERE user_id=? AND id IN ({marks})", (user_id, *clean)
    ).fetchall()
    return {item[0]: item[1] for item in found}


def insert_event(conn, user_id, rid, kind, from_status, to_status, occurrence_due_utc, actor,
                 actor_bot_id, client, detail, created_at) -> None:
    conn.execute(
        """INSERT INTO reminder_events(user_id, reminder_id, kind, from_status, to_status, occurrence_due_utc,
           actor, actor_bot_id, client, detail, created_at)
           VALUES (?,?,?,?,?,?,?,?,?,?,?)""",
        (user_id, rid, kind, from_status, to_status, occurrence_due_utc, actor, actor_bot_id, client,
         detail, created_at),
    )


def count_open(conn, user_id: int, statuses, bot_id=None) -> int:
    marks = ",".join("?" * len(statuses))
    if bot_id is None:
        return conn.execute(
            f"SELECT COUNT(*) FROM reminders WHERE user_id=? AND status IN ({marks})",
            (user_id, *statuses),
        ).fetchone()[0]
    return conn.execute(
        f"""SELECT COUNT(*) FROM reminders WHERE user_id=? AND status IN ({marks})
            AND (bot_id=? OR assignee_bot_id=?)""",
        (user_id, *statuses, bot_id, bot_id),
    ).fetchone()[0]


def reminders_for_user(conn, user_id: int) -> list[dict]:
    return rows(conn.execute("SELECT * FROM reminders WHERE user_id=?", (user_id,)).fetchall())


def select_reminders(conn, user_id: int, *, status_filter, include_cancelled: bool, bot_id, created_by,
                     start, end, updated_since, before_id, limit: int) -> list[dict]:
    clauses = ["r.user_id=?"]
    args: list = [user_id]
    if status_filter:
        clauses.append(f"r.status IN ({','.join('?' * len(status_filter))})")
        args.extend(status_filter)
    elif status_filter is None and not include_cancelled:
        clauses.append("r.status!='cancelled'")
    if bot_id is not None:
        clauses.append("(r.bot_id=? OR r.assignee_bot_id=?)")
        args.extend([bot_id, bot_id])
    if created_by:
        clauses.append("r.created_by=?")
        args.append(created_by)
    if start:
        clauses.append("r.due_utc>=?")
        args.append(start)
    if end:
        clauses.append("r.due_utc<=?")
        args.append(end)
    if updated_since:
        clauses.append("r.updated_at>=?")
        args.append(updated_since)
    if before_id:
        clauses.append("r.id<?")
        args.append(int(before_id))
    sql = ("SELECT r.* FROM reminders r WHERE " + " AND ".join(clauses)
           + " ORDER BY r.due_utc IS NULL, r.due_utc, r.priority DESC, r.id LIMIT ?")
    args.append(limit)
    return rows(conn.execute(sql, args).fetchall())


def insert_reminder(conn, fields: dict) -> int:
    cols = ",".join(fields)
    marks = ",".join("?" * len(fields))
    return conn.execute(
        f"INSERT INTO reminders({cols}) VALUES ({marks})", tuple(fields.values())
    ).lastrowid


def conditional_update_reminder(conn, rid, user_id, version, from_statuses, values: dict) -> int:
    sets = ", ".join(f"{key}=?" for key in values)
    where_status = ",".join("?" * len(from_statuses))
    cur = conn.execute(
        f"UPDATE reminders SET {sets} WHERE id=? AND user_id=? AND version=? AND status IN ({where_status})",
        (*values.values(), rid, user_id, version, *from_statuses),
    )
    return cur.rowcount


def last_cancelled_from_status(conn, user_id: int, rid: int):
    prev = conn.execute(
        """SELECT from_status FROM reminder_events WHERE user_id=? AND reminder_id=? AND kind='cancelled'
           ORDER BY id DESC LIMIT 1""",
        (user_id, rid),
    ).fetchone()
    if prev and prev[0]:
        return prev[0]
    return None


def reminder_events(conn, user_id: int, rid: int) -> list[dict]:
    return rows(conn.execute(
        """SELECT id, kind, from_status, to_status, occurrence_due_utc, actor, actor_bot_id, client, detail, created_at
           FROM reminder_events WHERE user_id=? AND reminder_id=? ORDER BY id""",
        (user_id, rid),
    ).fetchall())


def find_duplicate_reminder(conn, user_id: int, bot_id: int, title: str, due_utc):
    return row(conn.execute(
        """SELECT * FROM reminders WHERE user_id=? AND bot_id=? AND title=?
           AND IFNULL(due_utc,'')=IFNULL(?,'') AND status!='cancelled' ORDER BY id DESC LIMIT 1""",
        (user_id, bot_id, title, due_utc),
    ).fetchone())


def due_reminder_ids(conn, now_iso: str) -> list[int]:
    found = conn.execute(
        """SELECT id FROM reminders WHERE
             (status='scheduled' AND due_utc IS NOT NULL AND due_utc<=?)
          OR (status='snoozed' AND snoozed_until IS NOT NULL AND snoozed_until<=?)
          OR status='due'""",
        (now_iso, now_iso),
    ).fetchall()
    return [item[0] for item in found]


def purge_cancelled_reminders(conn, cutoff: str) -> int:
    cur = conn.execute(
        "DELETE FROM reminders WHERE status='cancelled' AND cancelled_at IS NOT NULL AND cancelled_at<=?",
        (cutoff,),
    )
    return cur.rowcount


def purge_idempotency_keys(conn, cutoff: str) -> None:
    conn.execute("DELETE FROM idempotency_keys WHERE created_at<=?", (cutoff,))


def purge_expired_pending_actions(conn, now_iso: str) -> None:
    """过期 pending → expired（保留行供 UI / 审计）；更早的清理由对账决定。"""
    conn.execute(
        """UPDATE pending_actions
           SET status='expired', result=COALESCE(result, '已过期'), decided_at=?
           WHERE expires_at<=? AND status='pending'""",
        (now_iso, now_iso),
    )


def get_idempotency(user_id: int, key: str):
    with tx() as conn:
        return row(conn.execute(
            "SELECT status_code, body, created_at FROM idempotency_keys WHERE user_id=? AND key=?",
            (user_id, key),
        ).fetchone())


def put_idempotency(user_id: int, key: str, status: int, body: str, created_at: str) -> None:
    with tx() as conn:
        conn.execute(
            """INSERT OR REPLACE INTO idempotency_keys(user_id, key, status_code, body, created_at)
               VALUES (?,?,?,?,?)""",
            (user_id, key, status, body, created_at),
        )


def notification_by_dedupe(conn, user_id: int, dedupe_key: str):
    return row(conn.execute(
        "SELECT * FROM notifications WHERE user_id=? AND dedupe_key=?", (user_id, dedupe_key)
    ).fetchone())


def count_notifications(conn, user_id: int, category: str, since: str, *, bot_id=None, plugin_id=None) -> int:
    clauses = ["user_id=?", "category=?", "created_at>=?"]
    args: list = [user_id, category, since]
    if bot_id is not None:
        clauses.append("bot_id=?")
        args.append(bot_id)
    if plugin_id is not None:
        clauses.append("plugin_id=?")
        args.append(plugin_id)
    sql = "SELECT COUNT(*) FROM notifications WHERE " + " AND ".join(clauses)
    return conn.execute(sql, args).fetchone()[0]


def insert_notification(conn, values: tuple) -> int:
    cur = conn.execute(
        """INSERT INTO notifications(user_id, category, title, body, sensitive, bot_id, reminder_id, message_id,
               plugin_id, link, thread_id, dedupe_key, created_at, expires_at)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        values,
    )
    return cur.lastrowid


def insert_inbox_delivery(conn, nid, user_id, created: str) -> None:
    conn.execute(
        """INSERT INTO notification_deliveries(notification_id, user_id, channel, device_id, state, attempts,
               updated_at) VALUES (?,?,?,?,?,?,?)""",
        (nid, user_id, "inbox", None, "delivered", 0, created),
    )


def insert_local_delivery(conn, nid, user_id, device_id, state, error, created: str) -> None:
    conn.execute(
        """INSERT INTO notification_deliveries(notification_id, user_id, channel, device_id, state, attempts,
               last_error, updated_at) VALUES (?,?,?,?,?,?,?,?)""",
        (nid, user_id, "local", device_id, state, 0, error, created),
    )


def notification_by_id(conn, nid: int):
    return row(conn.execute("SELECT * FROM notifications WHERE id=?", (nid,)).fetchone())


def select_notifications(conn, user_id: int, *, unread: bool, category, before_id, limit: int) -> list[dict]:
    clauses = ["user_id=?"]
    args: list = [user_id]
    if unread:
        clauses.append("read_at IS NULL")
    if category:
        clauses.append("category=?")
        args.append(category)
    if before_id:
        clauses.append("id<?")
        args.append(int(before_id))
    sql = "SELECT * FROM notifications WHERE " + " AND ".join(clauses) + " ORDER BY id DESC LIMIT ?"
    return rows(conn.execute(sql, (*args, limit)).fetchall())


def unread_count(conn, user_id: int) -> int:
    return conn.execute(
        "SELECT COUNT(*) FROM notifications WHERE user_id=? AND read_at IS NULL", (user_id,)
    ).fetchone()[0]


def unread_by_category(conn, user_id: int) -> dict:
    found = conn.execute(
        "SELECT category, COUNT(*) FROM notifications WHERE user_id=? AND read_at IS NULL GROUP BY category",
        (user_id,),
    )
    return {item[0]: item[1] for item in found}


def notification_for_user(conn, nid: int, user_id: int):
    return row(conn.execute(
        "SELECT * FROM notifications WHERE id=? AND user_id=?", (nid, user_id)
    ).fetchone())


def set_notification_read(conn, nid: int, user_id: int, now: str) -> None:
    conn.execute("UPDATE notifications SET read_at=? WHERE id=? AND user_id=?", (now, nid, user_id))


def clear_notification_read(conn, nid: int, user_id: int) -> None:
    conn.execute("UPDATE notifications SET read_at=NULL WHERE id=? AND user_id=?", (nid, user_id))


def mark_notifications_read(conn, user_id: int, now: str, *, category=None, before_id=None) -> int:
    clauses = ["user_id=?", "read_at IS NULL"]
    args: list = [user_id]
    if category:
        clauses.append("category=?")
        args.append(category)
    if before_id:
        clauses.append("id<=?")
        args.append(int(before_id))
    cur = conn.execute(
        f"UPDATE notifications SET read_at=? WHERE {' AND '.join(clauses)}", (now, *args)
    )
    return cur.rowcount


def delete_notification(conn, nid: int, user_id: int) -> int:
    return conn.execute("DELETE FROM notifications WHERE id=? AND user_id=?", (nid, user_id)).rowcount


def mark_notification_opened(conn, nid: int, when: str) -> None:
    conn.execute(
        "UPDATE notifications SET opened_at=?, read_at=COALESCE(read_at, ?) WHERE id=?",
        (when, when, nid),
    )


def latest_delivery(conn, nid: int, user_id: int, channel: str, device_id):
    return row(conn.execute(
        """SELECT * FROM notification_deliveries WHERE notification_id=? AND user_id=? AND channel=?
           AND IFNULL(device_id,'')=IFNULL(?,'') ORDER BY id DESC LIMIT 1""",
        (nid, user_id, channel, device_id),
    ).fetchone())


def insert_reported_delivery(conn, nid, user_id, channel, device_id, state, when, delivered_at, opened_at) -> None:
    conn.execute(
        """INSERT INTO notification_deliveries(notification_id, user_id, channel, device_id, state, attempts,
               updated_at, delivered_at, opened_at) VALUES (?,?,?,?,?,?,?,?,?)""",
        (nid, user_id, channel, device_id, state, 1, when, delivered_at, opened_at),
    )


def advance_delivery(conn, state, when, delivered, opened, delivery_id) -> None:
    conn.execute(
        """UPDATE notification_deliveries SET state=?, attempts=attempts+1, updated_at=?,
           delivered_at=COALESCE(delivered_at, ?), opened_at=COALESCE(opened_at, ?) WHERE id=?""",
        (state, when, delivered, opened, delivery_id),
    )


def latest_delivery_state(conn, nid: int, user_id: int, channel: str):
    return conn.execute(
        """SELECT state FROM notification_deliveries WHERE notification_id=? AND user_id=? AND channel=?
           ORDER BY id DESC LIMIT 1""",
        (nid, user_id, channel),
    ).fetchone()


def purge_notifications(conn, cutoff: str) -> None:
    conn.execute("DELETE FROM notifications WHERE created_at<=?", (cutoff,))


def deliveries_for(conn, user_id: int, notification_id: int) -> list[dict]:
    return rows(conn.execute(
        "SELECT * FROM notification_deliveries WHERE user_id=? AND notification_id=? ORDER BY id",
        (user_id, notification_id),
    ).fetchall())


def prefs_row(conn, user_id: int):
    return row(conn.execute("SELECT * FROM notification_prefs WHERE user_id=?", (user_id,)).fetchone())


def upsert_prefs(conn, user_id: int, enabled: int, categories: str, muted_bots: str, quiet_enabled: int,
                 quiet_start: str, quiet_end: str, quiet_timezone: str, preview: str, updated_at: str) -> None:
    conn.execute(
        """INSERT INTO notification_prefs(user_id, enabled, categories, muted_bots, quiet_enabled,
               quiet_start, quiet_end, quiet_timezone, preview, updated_at)
           VALUES (?,?,?,?,?,?,?,?,?,?)
           ON CONFLICT(user_id) DO UPDATE SET
             enabled=excluded.enabled, categories=excluded.categories, muted_bots=excluded.muted_bots,
             quiet_enabled=excluded.quiet_enabled, quiet_start=excluded.quiet_start,
             quiet_end=excluded.quiet_end, quiet_timezone=excluded.quiet_timezone,
             preview=excluded.preview, updated_at=excluded.updated_at""",
        (user_id, enabled, categories, muted_bots, quiet_enabled, quiet_start, quiet_end, quiet_timezone,
         preview, updated_at),
    )


def clear_apns_token_elsewhere(conn, token: str, user_id: int, device_id: str) -> None:
    conn.execute(
        """UPDATE push_devices SET apns_token=NULL
           WHERE apns_token=? AND NOT (user_id=? AND device_id=?)""",
        (token, user_id, device_id),
    )


def device_by_ids(conn, user_id: int, device_id: str):
    return row(conn.execute(
        "SELECT * FROM push_devices WHERE user_id=? AND device_id=?", (user_id, device_id)
    ).fetchone())


def update_device(conn, device_pk: int, fields: dict) -> None:
    sets = ", ".join(f"{key}=?" for key in fields)
    conn.execute(f"UPDATE push_devices SET {sets} WHERE id=?", (*fields.values(), device_pk))


def insert_device(conn, user_id, device_id, platform, token, apns_env, app_version, os_version, timezone_name,
                  local_reminders, now: str) -> None:
    conn.execute(
        """INSERT INTO push_devices(user_id, device_id, platform, apns_token, apns_env, app_version,
               os_version, timezone, local_reminders, disabled_at, last_seen_at, created_at)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?)""",
        (user_id, device_id, platform, token, apns_env, app_version, os_version, timezone_name,
         local_reminders, None, now, now),
    )


def unregister_device(conn, now: str, user_id: int, device_id: str) -> int:
    cur = conn.execute(
        """UPDATE push_devices SET disabled_at=?, local_reminders=0
           WHERE user_id=? AND device_id=? AND disabled_at IS NULL""",
        (now, user_id, device_id),
    )
    return cur.rowcount


def disable_user_devices(conn, user_id: int, now: str) -> None:
    conn.execute(
        "UPDATE push_devices SET disabled_at=? WHERE user_id=? AND disabled_at IS NULL",
        (now, user_id),
    )


def active_devices(conn, user_id: int) -> list[dict]:
    return rows(conn.execute(
        "SELECT * FROM push_devices WHERE user_id=? AND disabled_at IS NULL", (user_id,)
    ).fetchall())
