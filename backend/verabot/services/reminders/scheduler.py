"""到时、错过、重复推进、补跑。

Mac 睡眠或进程重启后，下一轮 tick 会处理全部积压，不依赖「上次跑到哪」。
一次性提醒按宽限期进入 due 或 missed。
重复提醒如果已经错过多次，只记一条「错过 N 次」，推进到下一个未来时间，不补发通知。
每次状态变化都是带 version / status 条件的 UPDATE，和用户同时操作时只有一方成功。
"""
from __future__ import annotations

import asyncio
import logging
import os
from datetime import timedelta

from ... import db
from ...db import reminder_store as store
from . import clock
from .service import (
    GRACE,
    ReminderError,
    _apply,
    _fetch,
    _parse_stored,
    missed_occurrences,
    project_next_future,
)

log = logging.getLogger("verabot.reminders")
INTERVAL_SECONDS = 30


def _should_notify(row) -> bool:
    return bool(row.get("notify")) and bool(row.get("due_utc") or row.get("snoozed_until"))


def _fire(c, row, *, when_iso: str, dedupe_suffix: str):
    from ..notify.dispatcher import notify
    public = _apply(
        c, row["user_id"], row["id"], expected_version=row["version"],
        from_statuses=(row["status"],),
        values={"status": "due", "snoozed_until": None},
        kind="fired", actor="system", client="scheduler",
        occurrence_due_utc=row.get("due_utc"), detail={"at": when_iso})
    if _should_notify(row):
        notify(
            row["user_id"], category="reminder", title=row.get("title") or row.get("content") or "提醒",
            body=None, reminder_id=row["id"], bot_id=row.get("assignee_bot_id") or row.get("bot_id"),
            link=f"reminder/{row['id']}", thread_id="reminders",
            dedupe_key=f"reminder:{row['id']}:{dedupe_suffix}",
            created_by=row.get("created_by"), conn=c)
    return public


def _miss_forward(c, row, now, count: int):
    nxt = project_next_future(row, now) if row.get("rrule") else None
    detail = {"missed_count": count, "summary": f"错过 {count} 次"}
    if nxt:
        values = nxt
    elif row.get("rrule"):
        values = {"status": "done", "snoozed_until": None, "completed_at": clock.iso_utc(now)}
    else:
        values = {"status": "missed", "snoozed_until": None}
    return _apply(
        c, row["user_id"], row["id"], expected_version=row["version"],
        from_statuses=(row["status"],), values=values, kind="missed", actor="system", client="scheduler",
        occurrence_due_utc=row.get("due_utc"), detail=detail)


def _handle(c, row, now) -> str:
    status = row["status"]
    if status == "snoozed":
        until = _parse_stored(row.get("snoozed_until"))
        if until and until <= now:
            _fire(c, row, when_iso=clock.iso_utc(until), dedupe_suffix=f"snooze:{clock.iso_utc(until)}")
            return "fired"
        return "idle"
    due = _parse_stored(row.get("due_utc"))
    if status == "scheduled":
        if due is None or due > now:
            return "idle"
        if row.get("rrule"):
            passed = missed_occurrences(row, now)
            count = max(1, len(passed))
            boundary = due + GRACE
            nxt_time = None
            projected = project_next_future(row, due)  # 紧接着的下一次
            if projected and projected.get("due_utc"):
                nxt_time = _parse_stored(projected["due_utc"])
            grace_end = boundary if nxt_time is None else min(boundary, nxt_time)
            if count <= 1 and now < grace_end:
                _fire(c, row, when_iso=clock.iso_utc(due), dedupe_suffix=row.get("due_utc") or clock.iso_utc(due))
                return "fired"
            _miss_forward(c, row, now, count)
            return "catchup"
        if now - due <= GRACE:
            _fire(c, row, when_iso=clock.iso_utc(due), dedupe_suffix=row.get("due_utc") or clock.iso_utc(due))
            return "fired"
        _apply(
            c, row["user_id"], row["id"], expected_version=row["version"], from_statuses=("scheduled",),
            values={"status": "missed"}, kind="missed", actor="system", client="scheduler",
            occurrence_due_utc=row.get("due_utc"), detail={"missed_count": 1, "summary": "错过 1 次"})
        return "missed"
    if status == "due":
        if due is None:
            return "idle"
        if row.get("rrule"):
            passed = missed_occurrences(row, now)
            nxt_time = None
            projected = project_next_future(row, due)
            if projected and projected.get("due_utc"):
                nxt_time = _parse_stored(projected["due_utc"])
            grace_end = due + GRACE if nxt_time is None else min(due + GRACE, nxt_time)
            if now < grace_end:
                return "idle"
            # 已经响过这一次。之后的积压算错过，不补发。
            count = max(1, len(passed))
            _miss_forward(c, row, now, count)
            return "missed"
        if now - due > GRACE:
            _apply(
                c, row["user_id"], row["id"], expected_version=row["version"], from_statuses=("due",),
                values={"status": "missed"}, kind="missed", actor="system", client="scheduler",
                occurrence_due_utc=row.get("due_utc"), detail={"missed_count": 1})
            return "missed"
    return "idle"


def tick(now=None) -> dict:
    now = now or clock.now()
    stats = {"fired": 0, "missed": 0, "catchup": 0, "purged": 0}
    with db.tx() as c:
        ids = store.due_reminder_ids(c, clock.iso_utc(now))
    for rid in ids:
        try:
            with db.tx() as c:
                row = store.fetch_reminder_by_id(c, rid)
                if row is None:
                    continue
                kind = _handle(c, row, now)
            if kind in stats:
                stats[kind] += 1
        except ReminderError:
            continue
        except Exception:
            log.exception("reminder tick failed id=%s", rid)
    _purge(now, stats)
    return stats


def _purge(now, stats):
    from ..notify.dispatcher import purge_old
    cutoff = clock.iso_utc(now - timedelta(days=30))
    day = clock.iso_utc(now - timedelta(hours=24))
    with db.tx() as c:
        stats["purged"] = store.purge_cancelled_reminders(c, cutoff)
        store.purge_idempotency_keys(c, day)
        store.purge_expired_pending_actions(c, clock.iso_utc(now))
    purge_old(now)


async def loop():
    if os.getenv("VERABOT_SCHEDULER", "1") == "0":
        return
    while True:
        try:
            tick()
        except Exception:
            log.exception("reminder scheduler tick failed")
        try:
            await asyncio.sleep(INTERVAL_SECONDS)
        except asyncio.CancelledError:
            break
