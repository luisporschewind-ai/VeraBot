"""统一事项：列表 / 详情 / 清单；动作复用提醒状态机。不暴露步骤、租约、token。"""
from __future__ import annotations

import json
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from ... import db
from ...core.config import TIMEZONE
from ...db import item_store, reminder_store
from ..reminders import clock, service as reminder_service
from ..reminders.service import ReminderError, to_public

CHECKLIST_MAX = 50
CHECKLIST_TEXT_MAX = 200
STATUS_LABELS = {
    "pending": "待执行",
    "running": "正在处理",
    "needs_user": "等你处理",
    "done": "已完成",
    "failed": "未完成",
}


def _parse(text: str | None) -> datetime | None:
    if not text:
        return None
    return datetime.fromisoformat(text.replace("Z", "+00:00"))


def _short(text: str | None, limit: int = 120) -> str | None:
    if not text:
        return None
    text = str(text).strip()
    if not text:
        return None
    return text if len(text) <= limit else text[: limit - 1] + "…"


def _task_summary(c, user_id: int, row: dict) -> dict | None:
    kind = row.get("task_kind")
    tid = row.get("task_id")
    if not kind or tid is None:
        return None
    if kind == "scheduled":
        task = item_store.scheduled_task_row(c, user_id, int(tid))
        if task is None:
            return {"kind": "scheduled", "id": int(tid), "status": "未完成", "status_key": "failed",
                    "next_run": None, "last_result_summary": "任务已结束", "needs_user": False,
                    "message_id": None, "bot_id": row.get("assignee_bot_id") or row.get("bot_id")}
        run = item_store.latest_scheduled_run(c, int(tid))
        state = task.get("state") or "active"
        run_state = (run or {}).get("state")
        needs_user = False
        if state == "completed":
            key = "done"
        elif state == "paused":
            key = "failed"
        elif run_state in {"running", "queued", "retry_wait"}:
            key = "running"
        elif run_state in {"failed", "interrupted", "cancelled"}:
            key = "failed"
        elif run_state == "succeeded" and state == "active":
            key = "pending"
        else:
            key = "pending"
        summary = _short((run or {}).get("result_text") or (run or {}).get("error_summary"))
        return {
            "kind": "scheduled", "id": int(tid), "status": STATUS_LABELS[key], "status_key": key,
            "next_run": task.get("next_run_at_utc"), "last_result_summary": summary,
            "needs_user": needs_user, "message_id": (run or {}).get("message_id"),
            "bot_id": task.get("bot_id"), "title": task.get("title"),
        }
    task = item_store.owned_task_row(c, user_id, int(tid))
    if task is None:
        return {"kind": "owned", "id": int(tid), "status": "未完成", "status_key": "failed",
                "next_run": None, "last_result_summary": "任务已结束", "needs_user": False,
                "message_id": None, "bot_id": row.get("assignee_bot_id") or row.get("bot_id")}
    state = task.get("state") or "queued"
    needs_user = state in {"awaiting_user", "awaiting_approval"}
    if needs_user:
        key = "needs_user"
    elif state in {"running", "queued", "retry_wait"}:
        key = "running" if state == "running" else "pending"
    elif state == "completed":
        key = "done"
    else:
        key = "failed"
    step = item_store.latest_owned_result(c, int(tid))
    summary = None
    message_id = None
    if step:
        message_id = step.get("message_id")
        raw = step.get("result_json")
        try:
            payload = json.loads(raw) if raw else {}
        except (TypeError, ValueError):
            payload = {}
        if isinstance(payload, dict):
            summary = _short(payload.get("text") or payload.get("summary") or payload.get("result"))
        elif isinstance(payload, str):
            summary = _short(payload)
    return {
        "kind": "owned", "id": int(tid), "status": STATUS_LABELS[key], "status_key": key,
        "next_run": None, "last_result_summary": summary, "needs_user": needs_user,
        "message_id": message_id, "bot_id": task.get("owner_bot_id"), "title": task.get("goal"),
    }


def to_item(row: dict, *, names: dict | None = None, now=None, checklist=None, task=None) -> dict:
    out = to_public(row, names=names, now=now)
    out["task_kind"] = row.get("task_kind")
    out["task_id"] = row.get("task_id")
    out["source_kind"] = row.get("source_kind")
    out["checklist_done"] = int(row.get("checklist_done") or 0)
    out["checklist_total"] = int(row.get("checklist_total") or 0)
    if checklist is not None:
        out["checklist"] = [
            {"id": item["id"], "text": item["text"], "done": bool(item.get("done")),
             "position": int(item.get("position") or 0), "updated_at": item.get("updated_at")}
            for item in checklist
        ]
    out["task"] = task
    return out


def _names(c, user_id, rows):
    ids = {r.get("bot_id") for r in rows} | {r.get("assignee_bot_id") for r in rows}
    return reminder_store.bot_names(c, user_id, ids)


def list_items(user_id: int, *, view: str | None = None, bot_id: int | None = None,
               cursor: str | None = None, limit: int = 100) -> dict:
    if view is not None and view not in {"today", "planned", "todo", "bot", "done"}:
        raise ReminderError(422, "view 无效")
    limit = max(1, min(int(limit or 100), 200))
    before_id = int(cursor) if cursor else None
    now = clock.now()
    tz = ZoneInfo(TIMEZONE)
    local = now.astimezone(tz)
    day_start = local.replace(hour=0, minute=0, second=0, microsecond=0)
    day_end = day_start + timedelta(days=1)
    with db.tx() as c:
        rows = item_store.select_items(
            c, user_id, view=view, bot_id=bot_id, before_id=before_id, limit=limit + 1,
            now_utc=clock.iso_utc(now), today_start=clock.iso_utc(day_start),
            today_end=clock.iso_utc(day_end))
        names = _names(c, user_id, rows[:limit])
        items = []
        for row in rows[:limit]:
            task = _task_summary(c, user_id, row)
            items.append(to_item(row, names=names, now=now, task=task))
    next_cursor = str(rows[limit - 1]["id"]) if len(rows) > limit else None
    return {"items": items, "server_time": clock.iso_utc(now), "next_cursor": next_cursor}


def get_item(user_id: int, rid: int) -> dict:
    with db.tx() as c:
        row = item_store.fetch_item(c, user_id, rid)
        if row is None or row.get("status") == "cancelled":
            raise ReminderError(404, "事项不存在")
        names = _names(c, user_id, [row])
        checklist = item_store.list_checklist(c, user_id, rid)
        task = _task_summary(c, user_id, row)
        return to_item(row, names=names, checklist=checklist, task=task)


def _normalize_checklist(entries) -> list[dict]:
    if entries is None:
        return []
    if not isinstance(entries, list):
        raise ReminderError(422, "清单格式无效")
    if len(entries) > CHECKLIST_MAX:
        raise ReminderError(422, f"清单最多 {CHECKLIST_MAX} 项")
    out = []
    for index, entry in enumerate(entries):
        if isinstance(entry, str):
            text, done = entry, False
        elif isinstance(entry, dict):
            text = entry.get("text") or entry.get("title") or ""
            done = bool(entry.get("done"))
        else:
            raise ReminderError(422, "清单格式无效")
        text = str(text).strip()
        if not text:
            raise ReminderError(422, "清单项不能为空")
        if len(text) > CHECKLIST_TEXT_MAX:
            raise ReminderError(422, f"清单项最多 {CHECKLIST_TEXT_MAX} 个字")
        out.append({"text": text, "done": 1 if done else 0, "position": index})
    return out


def _write_checklist(c, user_id: int, rid: int, entries: list[dict]) -> list[dict]:
    item_store.delete_checklist(c, user_id, rid)
    now = clock.iso_utc(clock.now())
    for entry in entries:
        item_store.insert_checklist_item(
            c, user_id, rid, entry["text"], entry["done"], entry["position"], now)
    item_store.update_checklist_counts(c, user_id, rid)
    return item_store.list_checklist(c, user_id, rid)


def create_item(user_id: int, *, title: str, note: str | None = None, due_at: str | None = None,
                timezone_name: str | None = None, all_day: bool = False, rrule: str | None = None,
                priority: int = 0, assignee_bot_id: int | None = None, source_message_id: int | None = None,
                notify: bool | None = None, alert_offsets=None, checklist=None,
                source_kind: str | None = "manual", client: str = "ios", actor: str = "user",
                actor_bot_id: int | None = None, created_by: str = "user", bot_id: int | None = None) -> dict:
    if source_kind is not None and source_kind not in {"manual", "chat", "group", "feed", "migration"}:
        raise ReminderError(422, "source_kind 无效")
    entries = _normalize_checklist(checklist)
    created = reminder_service.create_reminder(
        user_id, title=title, note=note, due_at=due_at, timezone_name=timezone_name, all_day=all_day,
        rrule=rrule, priority=priority, assignee_bot_id=assignee_bot_id, source_message_id=source_message_id,
        notify=notify, alert_offsets=alert_offsets, created_by=created_by, bot_id=bot_id, client=client,
        actor=actor, actor_bot_id=actor_bot_id, source_kind=source_kind)
    if entries:
        with db.tx() as c:
            _write_checklist(c, user_id, created["id"], entries)
    return get_item(user_id, created["id"])


def update_item(user_id: int, rid: int, patch: dict, *, expected_version: int, actor="user",
                actor_bot_id=None, client="ios") -> dict:
    reminder_patch = {k: v for k, v in patch.items() if k != "source_kind"}
    if "source_kind" in patch:
        kind = patch["source_kind"]
        if kind is not None and kind not in {"manual", "chat", "group", "feed"}:
            raise ReminderError(422, "source_kind 无效")
    updated = reminder_service.update_reminder(
        user_id, rid, reminder_patch, expected_version=expected_version, actor=actor,
        actor_bot_id=actor_bot_id, client=client)
    if "source_kind" in patch:
        with db.tx() as c:
            item_store.set_item_fields(c, rid, user_id, {"source_kind": patch["source_kind"]})
    return get_item(user_id, updated["id"])


def replace_checklist(user_id: int, rid: int, entries, *, expected_version: int) -> dict:
    entries = _normalize_checklist(entries)
    with db.tx() as c:
        row = item_store.fetch_item(c, user_id, rid)
        if row is None or row.get("status") == "cancelled":
            raise ReminderError(404, "事项不存在")
        if int(row["version"]) != int(expected_version):
            raise ReminderError(409, "这条提醒已在别处修改", "version_conflict",
                               to_item(row, names=_names(c, user_id, [row]),
                                       checklist=item_store.list_checklist(c, user_id, rid),
                                       task=_task_summary(c, user_id, row)))
        _write_checklist(c, user_id, rid, entries)
        item_store.set_item_fields(c, rid, user_id, {
            "version": int(row["version"]) + 1,
            "updated_at": clock.iso_utc(clock.now()),
        })
    return get_item(user_id, rid)


def toggle_checklist(user_id: int, rid: int, cid: int, *, done: bool | None = None) -> dict:
    with db.tx() as c:
        row = item_store.fetch_item(c, user_id, rid)
        if row is None or row.get("status") == "cancelled":
            raise ReminderError(404, "事项不存在")
        item = item_store.fetch_checklist_item(c, user_id, rid, cid)
        if item is None:
            raise ReminderError(404, "清单项不存在")
        new_done = (0 if item.get("done") else 1) if done is None else (1 if done else 0)
        item_store.set_checklist_done(c, user_id, cid, new_done, clock.iso_utc(clock.now()))
        item_store.update_checklist_counts(c, user_id, rid)
    return get_item(user_id, rid)


def find_item_for_notification(user_id: int, *, source_kind: str | None = None,
                               source_id: str | None = None, reminder_id: int | None = None) -> dict | None:
    with db.tx() as c:
        if reminder_id is not None:
            row = item_store.fetch_item(c, user_id, int(reminder_id))
            if row and row.get("status") != "cancelled":
                return to_item(row, names=_names(c, user_id, [row]), task=_task_summary(c, user_id, row))
        if source_kind == "owned_task" and source_id:
            row = item_store.find_by_task(c, user_id, "owned", int(source_id))
        elif source_kind == "scheduled_task" and source_id:
            task_id = item_store.scheduled_run_task_id(c, int(source_id))
            if task_id is None:
                return None
            row = item_store.find_by_task(c, user_id, "scheduled", int(task_id))
        else:
            return None
        if row is None:
            return None
        return to_item(row, names=_names(c, user_id, [row]), task=_task_summary(c, user_id, row))
