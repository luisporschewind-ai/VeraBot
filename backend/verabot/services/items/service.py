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
        history = [
            {"at": r.get("finished_at") or r.get("created_at"), "ok": r.get("state") == "succeeded"}
            for r in item_store.scheduled_runs_history(c, int(tid))
        ]
        return {
            "kind": "scheduled", "id": int(tid), "status": STATUS_LABELS[key], "status_key": key,
            "next_run": task.get("next_run_at_utc"), "last_result_summary": summary,
            "needs_user": needs_user, "message_id": (run or {}).get("message_id"),
            "bot_id": task.get("bot_id"), "title": task.get("title"), "history": history,
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
    wait = item_store.owned_open_wait(c, int(tid))
    history = [
        {"at": s.get("created_at"), "ok": s.get("status") == "completed"}
        for s in item_store.owned_steps_history(c, int(tid))
    ]
    return {
        "kind": "owned", "id": int(tid), "status": STATUS_LABELS[key], "status_key": key,
        "next_run": None, "last_result_summary": summary, "needs_user": needs_user,
        "message_id": message_id, "bot_id": task.get("owner_bot_id"), "title": task.get("goal"),
        "history": history, "wait_question": (wait or {}).get("question"),
        "wait_action_id": (wait or {}).get("action_id"),
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
                actor_bot_id: int | None = None, created_by: str = "user", bot_id: int | None = None,
                task: dict | None = None, idempotency_key: str | None = None) -> dict:
    if source_kind is not None and source_kind not in {"manual", "chat", "group", "feed", "migration"}:
        raise ReminderError(422, "source_kind 无效")
    task_kind = task_id = None
    if task:
        task_kind, task_id, task_due, task_assignee = _create_task(
            user_id, task, title=title, idempotency_key=idempotency_key)
        if assignee_bot_id is None:
            assignee_bot_id = task_assignee
        if task_due and due_at is None:
            due_at = task_due
        if notify is None:
            notify = False
    entries = _normalize_checklist(checklist)
    created = reminder_service.create_reminder(
        user_id, title=title, note=note, due_at=due_at, timezone_name=timezone_name, all_day=all_day,
        rrule=rrule, priority=priority, assignee_bot_id=assignee_bot_id, source_message_id=source_message_id,
        notify=notify, alert_offsets=alert_offsets, created_by=created_by, bot_id=bot_id, client=client,
        actor=actor, actor_bot_id=actor_bot_id, source_kind=source_kind,
        task_kind=task_kind, task_id=task_id)
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


# ---------------------------------------------------------------------------
# P2：交给 Bot（创建任务 + 关联、操作代理、写回同步、propose_task）
# ---------------------------------------------------------------------------

TASK_MODES = ("once", "repeat", "owned")
SCHEDULED_REPEATS = ("daily", "weekdays", "weekly")


def _validate_task_spec(task: dict) -> dict:
    if not isinstance(task, dict):
        raise ReminderError(422, "task 格式无效")
    mode = task.get("mode") or "once"
    if mode not in TASK_MODES:
        raise ReminderError(422, "执行方式无效")
    instruction = str(task.get("instruction") or "").strip()
    if not instruction:
        raise ReminderError(422, "请说明交给 Bot 做什么")
    if len(instruction) > 2000:
        raise ReminderError(422, "任务内容最多 2000 个字")
    bot_id = task.get("bot_id")
    if bot_id is None or not isinstance(bot_id, int) or bot_id <= 0:
        raise ReminderError(422, "请选择负责的 Bot")
    out = {"mode": mode, "instruction": instruction, "bot_id": int(bot_id)}
    if mode in ("once", "repeat"):
        start_at = str(task.get("start_at") or "").strip()
        if not start_at:
            raise ReminderError(422, "请选择任务执行时间")
        out["start_at"] = start_at
        out["timezone"] = task.get("timezone") or TIMEZONE
        if mode == "repeat":
            repeat = task.get("repeat") or "daily"
            if repeat not in SCHEDULED_REPEATS:
                raise ReminderError(422, "重复规则无效")
            out["repeat"] = repeat
            weekdays = task.get("weekdays") or []
            if repeat == "weekly":
                if not isinstance(weekdays, list) or not weekdays or any(
                        not isinstance(d, int) or d not in range(7) for d in weekdays):
                    raise ReminderError(422, "每周规则需要不重复的星期（0–6）")
            out["weekdays"] = sorted(set(int(d) for d in weekdays))
    else:
        criteria = str(task.get("completion_criteria") or "").strip()
        if not criteria:
            raise ReminderError(422, "持续任务需要完成标准")
        out["completion_criteria"] = criteria
        out["token_limit"] = task.get("token_limit")
    return out


def _create_task(user_id: int, task: dict, *, title: str, idempotency_key: str | None):
    spec = _validate_task_spec(task)
    bot = db.get_bot(user_id, spec["bot_id"])
    if bot is None:
        raise ReminderError(422, "负责的 Bot 不存在")
    key = idempotency_key or uuid_hex()
    if spec["mode"] == "owned":
        from ..owned_tasks import service as owned_service
        from ..primary_bot import get as primary_get
        if not primary_get(user_id)["active_enabled"]:
            raise ReminderError(409, "持续任务需要先开启「允许主动任务」", "active_disabled")
        created = owned_service.create(
            user_id,
            {"bot_id": spec["bot_id"], "goal": title[:200],
             "completion_criteria": spec["completion_criteria"],
             "token_limit": spec.get("token_limit") or 20000},
            key,
        )
        return "owned", created["id"], None, spec["bot_id"]
    from ..scheduled_tasks import service as scheduled_service
    from ..scheduled_tasks.contracts import TaskError
    payload = {
        "bot_id": spec["bot_id"],
        "title": title[:200],
        "instruction": spec["instruction"],
        "start_at": spec["start_at"],
        "timezone": spec["timezone"],
        "repeat": spec["mode"] if spec["mode"] == "once" else spec.get("repeat", "daily"),
        "weekdays": spec.get("weekdays", []),
        "execution_mode": "read_only",
    }
    try:
        created = scheduled_service.create(user_id, payload, key)
    except TaskError as exc:
        raise ReminderError(exc.status, exc.message, exc.code) from exc
    return "scheduled", created["id"], created.get("next_run_at_utc"), spec["bot_id"]


def _task_row(user_id: int, kind: str, task_id: int):
    with db.tx() as c:
        if kind == "scheduled":
            return item_store.scheduled_task_row(c, user_id, task_id)
        return item_store.owned_task_row(c, user_id, task_id)


def task_action(user_id: int, rid: int, action: str, *, message: str | None = None,
                idempotency_key: str | None = None) -> dict:
    from ..scheduled_tasks import service as scheduled_service
    from ..scheduled_tasks.contracts import TaskError
    from ..owned_tasks import service as owned_service
    with db.tx() as c:
        row = item_store.fetch_item(c, user_id, rid)
        if row is None or row.get("status") == "cancelled":
            raise ReminderError(404, "事项不存在")
        kind = row.get("task_kind")
        tid = row.get("task_id")
        if not kind or tid is None:
            raise ReminderError(409, "这件事项没有关联任务", "no_task")
    try:
        if kind == "scheduled":
            task = _task_row(user_id, "scheduled", int(tid))
            if task is None:
                raise TaskError("not_found", "任务已结束", 409)
            version = int(task["version"])
            if action in ("pause", "resume"):
                scheduled_service.transition(user_id, int(tid), action, version)
            elif action == "run":
                scheduled_service.run_now(user_id, int(tid), idempotency_key or uuid_hex())
            else:
                raise TaskError("invalid_action", "周期任务只支持 暂停/继续/立即执行", 422)
        elif kind == "owned":
            task = _task_row(user_id, "owned", int(tid))
            if task is None:
                raise TaskError("not_found", "任务已结束", 409)
            version = int(task["version"])
            if action == "stop":
                owned_service.control(user_id, int(tid), "stop", version)
            elif action == "continue":
                owned_service.control(user_id, int(tid), "continue", version)
            elif action == "input":
                text = (message or "").strip()
                if not text:
                    raise TaskError("invalid_input", "请填写回复内容", 422)
                owned_service.submit_input(user_id, int(tid), {"message": text},
                                           idempotency_key or uuid_hex(), version)
            else:
                raise TaskError("invalid_action", "持续任务只支持 停止/继续/回复", 422)
        else:
            raise TaskError("invalid_action", "不支持的任务类型", 422)
    except TaskError as exc:
        raise ReminderError(exc.status, exc.message, exc.code) from exc
    return get_item(user_id, rid)


def delete_item(user_id: int, rid: int, *, scope: str = "series", task: str = "keep",
                actor: str = "user", actor_bot_id: int | None = None, client: str = "ios") -> dict:
    with db.tx() as c:
        row = item_store.fetch_item(c, user_id, rid)
        if row is None or row.get("status") == "cancelled":
            raise ReminderError(404, "事项不存在")
        kind = row.get("task_kind")
        tid = row.get("task_id")
    if task == "stop" and kind and tid is not None:
        try:
            if kind == "scheduled":
                from ..scheduled_tasks import service as scheduled_service
                t = _task_row(user_id, "scheduled", int(tid))
                if t is not None:
                    scheduled_service.transition(user_id, int(tid), "delete", int(t["version"]))
            elif kind == "owned":
                from ..owned_tasks import service as owned_service
                t = _task_row(user_id, "owned", int(tid))
                if t is not None:
                    owned_service.control(user_id, int(tid), "stop", int(t["version"]))
        except Exception:
            import logging
            logging.getLogger("verabot.items").warning("stop linked task failed item=%s kind=%s", rid, kind)
    return reminder_service.cancel_reminder(user_id, rid, scope=scope, actor=actor,
                                            actor_bot_id=actor_bot_id, client=client)


def propose_task(user_id: int, bot: dict, spec: dict, *, source_message_id: int | None = None,
                 group_id: int | None = None) -> dict:
    """Bot 在对话里提议交办任务：冻结参数进 pending_actions，用户确认后才创建。"""
    from ..actions import create_propose_pending
    title = str(spec.get("title") or spec.get("goal") or "").strip()
    if not title:
        raise ReminderError(422, "请说明任务目标")
    merged = {**spec, "title": title[:200],
              "instruction": str(spec.get("instruction") or title).strip(),
              "bot_id": spec.get("bot_id") or bot.get("id")}
    clean = _validate_task_spec(merged)
    clean["title"] = merged["title"]
    return create_propose_pending(user_id, bot, clean, source_message_id=source_message_id,
                                  group_id=group_id)


def uuid_hex() -> str:
    import uuid
    return uuid.uuid4().hex
