"""统一事项（Items）的 SQL。清单与任务摘要查询；业务规则在 services/items。"""
from __future__ import annotations

from .database import row, rows


def fetch_item(conn, user_id: int, rid: int):
    return row(conn.execute("SELECT * FROM reminders WHERE id=? AND user_id=?", (rid, user_id)).fetchone())


def find_by_task(conn, user_id: int, task_kind: str, task_id: int):
    return row(conn.execute(
        "SELECT * FROM reminders WHERE user_id=? AND task_kind=? AND task_id=? AND status!='cancelled'",
        (user_id, task_kind, task_id),
    ).fetchone())


def select_items(conn, user_id: int, *, view: str | None, bot_id: int | None, before_id: int | None,
                 limit: int, now_utc: str, today_start: str, today_end: str) -> list[dict]:
    clauses = ["r.user_id=?", "r.status!='cancelled'"]
    args: list = [user_id]
    if bot_id is not None:
        clauses.append("(r.bot_id=? OR r.assignee_bot_id=?)")
        args.extend([bot_id, bot_id])
    if view == "today":
        clauses.append("r.status NOT IN ('done','missed')")
        clauses.append("r.due_utc IS NOT NULL")
        clauses.append("r.due_utc<?")
        args.append(today_end)
    elif view == "planned":
        clauses.append("r.status NOT IN ('done','missed')")
        clauses.append("r.task_id IS NULL")
        clauses.append("r.due_utc IS NOT NULL")
        clauses.append("r.due_utc>=?")
        args.append(today_end)
    elif view == "todo":
        clauses.append("r.status NOT IN ('done','missed')")
        clauses.append("r.task_id IS NULL")
        clauses.append("r.due_utc IS NULL")
    elif view == "bot":
        clauses.append("r.status NOT IN ('done','missed')")
        clauses.append("r.task_id IS NOT NULL")
    elif view == "done":
        clauses.append("r.status IN ('done','missed')")
    if before_id is not None:
        clauses.append("r.id<?")
        args.append(int(before_id))
    sql = ("SELECT r.* FROM reminders r WHERE " + " AND ".join(clauses)
           + " ORDER BY r.due_utc IS NULL, r.due_utc, r.priority DESC, r.id LIMIT ?")
    args.append(limit)
    return rows(conn.execute(sql, args).fetchall())


def list_checklist(conn, user_id: int, reminder_id: int) -> list[dict]:
    return rows(conn.execute(
        """SELECT id, text, done, position, updated_at FROM reminder_checklist
           WHERE user_id=? AND reminder_id=? ORDER BY position, id""",
        (user_id, reminder_id),
    ).fetchall())


def delete_checklist(conn, user_id: int, reminder_id: int) -> None:
    conn.execute("DELETE FROM reminder_checklist WHERE user_id=? AND reminder_id=?", (user_id, reminder_id))


def insert_checklist_item(conn, user_id: int, reminder_id: int, text: str, done: int, position: int,
                          updated_at: str) -> int:
    return conn.execute(
        """INSERT INTO reminder_checklist(user_id, reminder_id, text, done, position, updated_at)
           VALUES (?,?,?,?,?,?)""",
        (user_id, reminder_id, text, done, position, updated_at),
    ).lastrowid


def fetch_checklist_item(conn, user_id: int, reminder_id: int, cid: int):
    return row(conn.execute(
        "SELECT * FROM reminder_checklist WHERE id=? AND user_id=? AND reminder_id=?",
        (cid, user_id, reminder_id),
    ).fetchone())


def set_checklist_done(conn, user_id: int, cid: int, done: int, updated_at: str) -> int:
    cur = conn.execute(
        "UPDATE reminder_checklist SET done=?, updated_at=? WHERE id=? AND user_id=?",
        (done, updated_at, cid, user_id),
    )
    return cur.rowcount


def update_checklist_counts(conn, user_id: int, reminder_id: int) -> None:
    totals = conn.execute(
        """SELECT COALESCE(SUM(CASE WHEN done!=0 THEN 1 ELSE 0 END),0), COUNT(*)
           FROM reminder_checklist WHERE user_id=? AND reminder_id=?""",
        (user_id, reminder_id),
    ).fetchone()
    conn.execute(
        "UPDATE reminders SET checklist_done=?, checklist_total=?, updated_at=? WHERE id=? AND user_id=?",
        (totals[0], totals[1],
         conn.execute("SELECT strftime('%Y-%m-%dT%H:%M:%S+00:00','now')").fetchone()[0],
         reminder_id, user_id),
    )


def set_item_fields(conn, rid: int, user_id: int, fields: dict) -> None:
    if not fields:
        return
    sets = ", ".join(f"{key}=?" for key in fields)
    conn.execute(f"UPDATE reminders SET {sets} WHERE id=? AND user_id=?", (*fields.values(), rid, user_id))


def scheduled_task_row(conn, user_id: int, task_id: int):
    return row(conn.execute(
        "SELECT * FROM scheduled_tasks WHERE id=? AND user_id=? AND state!='deleted'",
        (task_id, user_id),
    ).fetchone())


def owned_task_row(conn, user_id: int, task_id: int):
    return row(conn.execute(
        "SELECT * FROM owned_tasks WHERE id=? AND user_id=?", (task_id, user_id)
    ).fetchone())


def latest_scheduled_run(conn, task_id: int):
    return row(conn.execute(
        """SELECT id, state, result_text, error_summary, finished_at, message_id
           FROM scheduled_task_runs WHERE task_id=? ORDER BY id DESC LIMIT 1""",
        (task_id,),
    ).fetchone())


def latest_owned_result(conn, task_id: int):
    return row(conn.execute(
        """SELECT s.id, s.status, s.result_json, s.message_id, s.created_at
           FROM owned_steps s WHERE s.task_id=? AND s.message_id IS NOT NULL
           ORDER BY s.id DESC LIMIT 1""",
        (task_id,),
    ).fetchone())


def scheduled_run_task_id(conn, run_id: int):
    found = conn.execute("SELECT task_id FROM scheduled_task_runs WHERE id=?", (run_id,)).fetchone()
    return found[0] if found else None
