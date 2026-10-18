"""P2 写回同步：任务状态变化 → 关联事项。

- owned 任务完成 → 事项自动完成（只完成事项，不动任务引擎）。
- scheduled / owned 任务被删除/停止 → 事项保留，解除关联并标注「任务已结束」。
- scheduled 每次调度推进后 → 事项下次时间跟随 next_run_at_utc。
"""
from __future__ import annotations

import logging
from datetime import datetime
from zoneinfo import ZoneInfo

from ... import db
from ...core.config import TIMEZONE
from ...db import item_store, reminder_store
from ..reminders import clock
from ..reminders import service as reminder_service

log = logging.getLogger("verabot.items.sync")


def _find(user_id: int, kind: str, task_id: int):
    with db.tx() as c:
        return item_store.find_by_task(c, user_id, kind, task_id)


def on_owned_completed(user_id: int, task_id: int) -> None:
    row = _find(user_id, "owned", task_id)
    if row is None:
        return
    try:
        reminder_service.complete_reminder(
            user_id, int(row["id"]), actor="bot",
            actor_bot_id=row.get("assignee_bot_id") or row.get("bot_id"), client="task")
    except Exception:
        log.exception("auto-complete linked item failed task=%s item=%s", task_id, row.get("id"))


def on_task_ended(user_id: int, kind: str, task_id: int) -> None:
    """任务已删除/停止：保留事项，解除关联并写入「任务已结束」事件。"""
    with db.tx(immediate=True) as c:
        row = item_store.find_by_task(c, user_id, kind, task_id)
        if row is None:
            return
        rid = int(row["id"])
        item_store.clear_task_link(c, rid, user_id, clock.iso_utc(clock.now()))
        reminder_store.insert_event(
            c, user_id, rid, "task_unlinked", row.get("status"), row.get("status"),
            row.get("due_utc"), "system", None, "task",
            '{"message": "任务已结束，事项已保留"}', clock.iso_utc(clock.now()),
        )
    from ..notify.dispatcher import notify
    try:
        notify(
            user_id, category="task_result",
            title="任务已结束，事项已保留",
            body=None, bot_id=row.get("assignee_bot_id") or row.get("bot_id"),
            link="inbox", thread_id=f"item:{rid}",
            dedupe_key=f"item-task-ended:{kind}:{task_id}",
            source_kind=f"{kind}_task", source_id=str(task_id), source_state="ended",
        )
    except Exception:
        log.exception("task-ended notification failed task=%s", task_id)


def on_scheduled_advanced(c, user_id: int, task_id: int) -> None:
    """在 scheduler 的同一事务里调用；把事项的 due 对齐到任务下一次执行。"""
    task = item_store.scheduled_task_row(c, user_id, task_id)
    if task is None:
        return
    row = item_store.find_by_task(c, user_id, "scheduled", task_id)
    if row is None:
        return
    nxt = task.get("next_run_at_utc")
    if not nxt:
        return
    try:
        parsed = datetime.fromisoformat(nxt.replace("Z", "+00:00"))
        tz = ZoneInfo(row.get("timezone") or TIMEZONE)
        local = parsed.astimezone(tz)
        due_at = local.isoformat(timespec="minutes")
        due_utc = clock.iso_utc(parsed)
        version = int(row.get("version") or 1) + 1
        item_store.advance_due(c, int(row["id"]), user_id, due_at, due_utc, version,
                               clock.iso_utc(clock.now()))
    except Exception:
        log.exception("scheduled advance sync failed task=%s", task_id)
