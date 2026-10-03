"""提醒状态机与用户 / Bot 共用的读写。所有查询都带 user_id。"""
from __future__ import annotations

import json
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from ... import db
from ...core.config import TIMEZONE
from ...db import reminder_store as store
from . import clock
from .rrule import RRuleError, between, count_limit, from_preset, label, next_after, normalize

OPEN_STATUSES = ("scheduled", "due", "snoozed", "missed")
ACTIVE_FOR_BOT = OPEN_STATUSES + ("done",)
USER_LIMIT = 500
BOT_LIMIT = 50
TITLE_MAX = 200
NOTE_MAX = 2000
GRACE = timedelta(hours=24)
KEEP_DAYS = 30
PAST_TOLERANCE = timedelta(minutes=1)


class ReminderError(Exception):
    def __init__(self, status: int, message: str, code: str | None = None, reminder: dict | None = None):
        super().__init__(message)
        self.status = status
        self.message = message
        self.code = code
        self.reminder = reminder


def _tz(name: str | None) -> ZoneInfo:
    try:
        return ZoneInfo(name or TIMEZONE)
    except Exception as exc:
        raise ReminderError(422, "时区无效") from exc


def _parse_stored(text: str | None) -> datetime | None:
    if not text:
        return None
    return datetime.fromisoformat(text.replace("Z", "+00:00"))


def _loads(text, default):
    try:
        return json.loads(text) if text else default
    except (TypeError, ValueError):
        return default


def _require_bot(c, user_id: int, bot_id):
    if bot_id is None:
        return
    if not store.bot_exists(c, user_id, bot_id):
        raise ReminderError(404, "Bot 不存在")


def _require_message(c, user_id: int, message_id):
    if message_id is None:
        return
    if not store.message_exists(c, user_id, message_id):
        raise ReminderError(404, "消息不存在")


def _local_due(row) -> datetime | None:
    """due_at 存的是当时的偏移量。重复展开要回到 IANA 时区，夏令时后仍是本地同一时刻。"""
    parsed = _parse_stored(row.get("due_at"))
    if parsed is None:
        return None
    try:
        zone = ZoneInfo(row.get("timezone") or TIMEZONE)
    except Exception:
        return parsed
    return parsed.replace(tzinfo=None).replace(tzinfo=zone)


def repeat_label(row) -> str | None:
    return label(row.get("rrule"), _local_due(row))


def compute_next_fires(row, now: datetime | None = None, limit: int = 10) -> list[str]:
    """未来触发时间（UTC ISO）。稍后中的提醒把 snoozed_until 放在最前。"""
    now = now or clock.now()
    found: list[datetime] = []
    if row.get("status") == "snoozed":
        snooze = _parse_stored(row.get("snoozed_until"))
        if snooze and snooze > now:
            found.append(snooze.astimezone(ZoneInfo("UTC")))
    rule = row.get("rrule")
    due = _local_due(row)
    if rule and due is not None:
        cap = count_limit(rule)
        index = int(row.get("occurrence_index") or 1)
        cursor = due
        step = 0
        while len(found) < limit and step < 400:
            step += 1
            if cap is not None and index + step - 1 > cap:
                break
            utc = cursor.astimezone(ZoneInfo("UTC"))
            if utc > now:
                found.append(utc)
            nxt = next_after(rule, due, cursor)
            if nxt is None or nxt <= cursor:
                break
            cursor = nxt
    else:
        due_utc = _parse_stored(row.get("due_utc"))
        if due_utc and due_utc > now:
            found.append(due_utc.astimezone(ZoneInfo("UTC")))
    uniq: list[datetime] = []
    for item in sorted(found):
        if not uniq or abs((item - uniq[-1]).total_seconds()) > 30:
            uniq.append(item)
    return [clock.iso_utc(item) for item in uniq[:limit]]


def to_public(row: dict, *, names: dict | None = None, now: datetime | None = None) -> dict:
    names = names or {}
    title = row.get("title") or row.get("content") or ""
    offsets = _loads(row.get("alert_offsets"), [0])
    if not isinstance(offsets, list):
        offsets = [0]
    bot_id = row.get("bot_id")
    assignee = row.get("assignee_bot_id")
    status = row.get("status") or ("done" if row.get("done") else "scheduled")
    return {
        "id": row["id"],
        "title": title,
        "content": title,
        "note": row.get("note"),
        "due_at": row.get("due_at"),
        "due_utc": row.get("due_utc"),
        "timezone": row.get("timezone") or TIMEZONE,
        "all_day": bool(row.get("all_day")),
        "rrule": row.get("rrule"),
        "repeat_label": repeat_label(row),
        "next_fires": compute_next_fires(row, now=now),
        "status": status,
        "snoozed_until": row.get("snoozed_until"),
        "priority": int(row.get("priority") or 0),
        "created_by": row.get("created_by") or "user",
        "bot_id": bot_id,
        "source_bot_id": bot_id,
        "bot_name": names.get(bot_id) if bot_id in names else row.get("bot_name"),
        "assignee_bot_id": assignee,
        "assignee_bot_name": names.get(assignee) if assignee in names else row.get("assignee_bot_name"),
        "source_message_id": row.get("source_message_id"),
        "notify": bool(row.get("notify")) if row.get("due_at") or row.get("due_utc") else False,
        "alert_offsets": [int(x) for x in offsets][:3],
        "version": int(row.get("version") or 1),
        "done": 1 if status == "done" else 0,
        "completed_at": row.get("completed_at"),
        "cancelled_at": row.get("cancelled_at"),
        "created_at": row.get("created_at"),
        "updated_at": row.get("updated_at"),
    }


def _fetch(c, user_id: int, rid: int):
    return store.fetch_reminder(c, user_id, rid)


def _names_for(c, user_id: int, rows: list[dict]) -> dict:
    ids = {r.get("bot_id") for r in rows} | {r.get("assignee_bot_id") for r in rows}
    return store.bot_names(c, user_id, ids)


def _public_id(c, user_id: int, rid: int, now: datetime | None = None) -> dict:
    row = _fetch(c, user_id, rid)
    if row is None:
        raise ReminderError(404, "提醒不存在")
    names = _names_for(c, user_id, [row])
    out = to_public(row, names=names, now=now)
    if row.get("bot_id") and out["bot_name"] is None:
        out["bot_name"] = None
    return out


def _event(c, user_id, rid, kind, actor, from_status, to_status, *, actor_bot_id=None, client=None,
           occurrence_due_utc=None, detail=None):
    store.insert_event(
        c, user_id, rid, kind, from_status, to_status, occurrence_due_utc, actor, actor_bot_id, client,
        json.dumps(detail, ensure_ascii=False) if detail is not None else None, clock.iso_utc(clock.now()),
    )


def _check_text(title: str, note: str | None):
    title = (title or "").strip()
    if not title:
        raise ReminderError(422, "标题不能为空")
    if len(title) > TITLE_MAX:
        raise ReminderError(422, "标题最多 200 个字")
    if note is not None and len(note) > NOTE_MAX:
        raise ReminderError(422, "备注最多 2000 个字")
    return title, (note.strip() if note and note.strip() else None)


def _check_priority(value) -> int:
    try:
        number = int(value if value is not None else 0)
    except (TypeError, ValueError):
        raise ReminderError(422, "优先级无效") from None
    if number not in (0, 1, 2, 3):
        raise ReminderError(422, "优先级无效")
    return number


def _check_offsets(value) -> str:
    if value is None:
        return "[0]"
    if not isinstance(value, list) or len(value) > 3:
        raise ReminderError(422, "提前提醒最多 3 个")
    out = []
    for item in value:
        try:
            minutes = int(item)
        except (TypeError, ValueError):
            raise ReminderError(422, "提前提醒无效") from None
        if minutes < -7 * 24 * 60 or minutes > 0:
            raise ReminderError(422, "提前提醒无效")
        out.append(minutes)
    return json.dumps(out or [0])


def _build_when(due_at, timezone_name, all_day, *, allow_past=False):
    tz = _tz(timezone_name)
    if not due_at:
        return None, None, tz.key
    try:
        parsed = datetime.fromisoformat(str(due_at).strip().replace("Z", "+00:00"))
    except ValueError:
        raise ReminderError(422, "时间格式无效，请使用 ISO8601") from None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=tz)
    else:
        parsed = parsed.astimezone(tz)
    if all_day:
        parsed = parsed.replace(hour=9, minute=0, second=0, microsecond=0)
    else:
        parsed = parsed.replace(second=0, microsecond=0)
    if not allow_past and parsed.astimezone(ZoneInfo("UTC")) < clock.now() - PAST_TOLERANCE:
        raise ReminderError(422, "不能把提醒设在过去")
    return clock.iso_local(parsed), clock.iso_utc(parsed), tz.key


def _open_count(c, user_id: int, bot_id=None) -> int:
    return store.count_open(c, user_id, OPEN_STATUSES, bot_id)


def _bucket(row, now: datetime) -> str | None:
    status = row.get("status")
    if status == "cancelled":
        return None
    tz = _tz(row.get("timezone") or TIMEZONE)
    if status in {"done", "missed"}:
        stamp = _parse_stored(row.get("completed_at") or row.get("updated_at") or row.get("created_at"))
        if stamp and now - stamp > timedelta(days=KEEP_DAYS):
            return None
        return status
    if status == "due":
        return "due"
    when = _parse_stored(row.get("snoozed_until") if status == "snoozed" else None) or _parse_stored(row.get("due_utc"))
    if when is None:
        return "undated"
    if when <= now and status == "scheduled":
        return "due"
    local_now = now.astimezone(tz)
    if when.astimezone(tz).date() == local_now.date():
        return "today"
    if when > now:
        return "upcoming"
    return "due"


def counts_for(c, user_id: int, now: datetime | None = None) -> dict:
    now = now or clock.now()
    rows = store.reminders_for_user(c, user_id)
    out = {"due": 0, "today": 0, "upcoming": 0, "undated": 0, "missed": 0, "done": 0}
    for row in rows:
        bucket = _bucket(row, now)
        if bucket in out:
            out[bucket] += 1
    return out


def list_reminders(user_id: int, *, status=None, bot_id=None, created_by=None, start=None, end=None,
                   updated_since=None, limit=200, before_id=None, include_cancelled=False) -> dict:
    now = clock.now()
    limit = max(1, min(int(limit or 200), 500))
    status_filter = None
    if status:
        status_filter = [s.strip() for s in str(status).split(",") if s.strip()]
    with db.tx() as c:
        rows = store.select_reminders(
            c, user_id, status_filter=status_filter, include_cancelled=include_cancelled, bot_id=bot_id,
            created_by=created_by, start=start, end=end, updated_since=updated_since, before_id=before_id,
            limit=limit)
        names = _names_for(c, user_id, rows)
        counted = counts_for(c, user_id, now)
    return {"reminders": [to_public(r, names=names, now=now) for r in rows],
            "server_time": clock.iso_utc(now), "counts": counted}


def get_reminder(user_id: int, rid: int) -> dict:
    with db.tx() as c:
        row = _fetch(c, user_id, rid)
        if row is None:
            raise ReminderError(404, "提醒不存在")
        names = _names_for(c, user_id, [row])
        return to_public(row, names=names)


def _insert(c, user_id: int, fields: dict) -> int:
    return store.insert_reminder(c, fields)


def create_reminder(user_id: int, *, title: str, note: str | None = None, due_at: str | None = None,
                    timezone_name: str | None = None, all_day: bool = False, rrule: str | None = None,
                    priority: int = 0, assignee_bot_id: int | None = None, source_message_id: int | None = None,
                    notify: bool | None = None, alert_offsets=None, created_by: str = "user",
                    bot_id: int | None = None, client: str = "ios", actor: str = "user",
                    actor_bot_id: int | None = None) -> dict:
    title, note = _check_text(title, note)
    priority = _check_priority(priority)
    tz_name = timezone_name or TIMEZONE
    _tz(tz_name)
    due_local, due_utc, tz_name = _build_when(due_at, tz_name, all_day)
    try:
        parsed_due = _parse_stored(due_local) if due_local else None
        rule = from_preset(rrule, parsed_due) if rrule else None
        if rule:
            rule = normalize(rule)
    except RRuleError as exc:
        raise ReminderError(422, "不支持的重复规则") from exc
    if rule and not due_local:
        raise ReminderError(422, "无日期待办不能设置重复")
    if notify is None:
        notify = bool(due_local)
    if not due_local:
        notify = False
    offsets = _check_offsets(alert_offsets)
    now = clock.iso_utc(clock.now())
    with db.tx() as c:
        _require_bot(c, user_id, assignee_bot_id)
        _require_bot(c, user_id, bot_id)
        _require_message(c, user_id, source_message_id)
        if _open_count(c, user_id) >= USER_LIMIT:
            raise ReminderError(422, "未结束的提醒已达上限（500）")
        owner = assignee_bot_id or bot_id
        if owner and _open_count(c, user_id, owner) >= BOT_LIMIT:
            raise ReminderError(422, "这个 Bot 的未结束提醒已达上限（50）")
        rid = _insert(c, user_id, {
            "user_id": user_id, "bot_id": bot_id, "content": title, "due_at": due_local, "done": 0,
            "created_at": now, "title": title, "note": note, "timezone": tz_name, "due_utc": due_utc,
            "all_day": 1 if all_day else 0, "rrule": rule, "occurrence_index": 1, "status": "scheduled",
            "snoozed_until": None, "priority": priority, "created_by": created_by,
            "assignee_bot_id": assignee_bot_id, "source_message_id": source_message_id, "client": client,
            "notify": 1 if notify else 0, "alert_offsets": offsets, "version": 1,
            "completed_at": None, "cancelled_at": None, "updated_at": now,
        })
        _event(c, user_id, rid, "created", actor, None, "scheduled", actor_bot_id=actor_bot_id, client=client,
               occurrence_due_utc=due_utc, detail={"fields": ["title", "due_at", "rrule"]})
        return _public_id(c, user_id, rid)


def _conflict(c, user_id, rid, code="version_conflict"):
    fresh = _fetch(c, user_id, rid)
    public = None
    if fresh:
        public = to_public(fresh, names=_names_for(c, user_id, [fresh]))
    message = "这条提醒已在别处修改" if code == "version_conflict" else "当前状态不能这样操作"
    raise ReminderError(409, message, code, public)


def _apply(c, user_id, rid, *, expected_version, from_statuses, values: dict, kind: str, actor: str,
           actor_bot_id=None, client=None, detail=None, occurrence_due_utc=None):
    row = _fetch(c, user_id, rid)
    if row is None:
        raise ReminderError(404, "提醒不存在")
    if expected_version is not None and int(row["version"]) != int(expected_version):
        _conflict(c, user_id, rid, "version_conflict")
    if row["status"] not in from_statuses:
        _conflict(c, user_id, rid, "invalid_transition")
    version = int(row["version"]) + 1
    values = {**values, "version": version, "updated_at": clock.iso_utc(clock.now()), "client": client or row.get("client")}
    values["done"] = 1 if values.get("status", row["status"]) == "done" else 0
    if "title" in values:
        values["content"] = values["title"]
    changed = store.conditional_update_reminder(c, rid, user_id, row["version"], from_statuses, values)
    if changed != 1:
        fresh = _fetch(c, user_id, rid)
        code = "invalid_transition" if fresh and fresh["status"] not in from_statuses else "version_conflict"
        _conflict(c, user_id, rid, code)
    _event(c, user_id, rid, kind, actor, row["status"], values.get("status", row["status"]),
           actor_bot_id=actor_bot_id, client=client, occurrence_due_utc=occurrence_due_utc or row.get("due_utc"),
           detail=detail)
    return _public_id(c, user_id, rid)


def _advance_values(row, now: datetime) -> dict | None:
    """重复提醒推进到下一次。没有下一次时返回 None（系列结束）。"""
    rule = row.get("rrule")
    due = _local_due(row)
    if not rule or due is None:
        return None
    cap = count_limit(rule)
    index = int(row.get("occurrence_index") or 1)
    if cap is not None and index >= cap:
        return None
    nxt = next_after(rule, due, due)
    if nxt is None:
        return None
    return {
        "due_at": clock.iso_local(nxt),
        "due_utc": clock.iso_utc(nxt),
        "occurrence_index": index + 1,
        "status": "scheduled",
        "snoozed_until": None,
        "completed_at": None,
        "done": 0,
    }


def update_reminder(user_id: int, rid: int, patch: dict, *, expected_version: int, actor="user",
                    actor_bot_id=None, client="ios", allow_rrule=True) -> dict:
    if expected_version is None:
        raise ReminderError(422, "缺少 expected_version")
    with db.tx() as c:
        row = _fetch(c, user_id, rid)
        if row is None:
            raise ReminderError(404, "提醒不存在")
        if row["status"] == "cancelled":
            _conflict(c, user_id, rid, "invalid_transition")
        values: dict = {}
        detail = {"fields": []}
        if "title" in patch or "note" in patch:
            title = patch.get("title", row.get("title") or row.get("content"))
            note = patch.get("note", row.get("note"))
            title, note = _check_text(title, note)
            values["title"] = title
            values["note"] = note
            detail["fields"] += ["title", "note"]
        timezone_name = patch.get("timezone", row.get("timezone") or TIMEZONE)
        all_day = bool(patch["all_day"]) if "all_day" in patch else bool(row.get("all_day"))
        if any(k in patch for k in ("due_at", "timezone", "all_day", "rrule")):
            due_text = patch["due_at"] if "due_at" in patch else row.get("due_at")
            if patch.get("due_at") == "" or patch.get("due_at") is None and "due_at" in patch:
                due_text = None
            due_local, due_utc, timezone_name = _build_when(due_text, timezone_name, all_day, allow_past=False) if due_text else (None, None, _tz(timezone_name).key)
            if "due_at" in patch or "all_day" in patch or "timezone" in patch:
                values["due_at"] = due_local
                values["due_utc"] = due_utc
                values["timezone"] = timezone_name
                values["all_day"] = 1 if all_day else 0
                detail["fields"].append("due_at")
                detail["due_at"] = [row.get("due_at"), due_local]
                if row["status"] in {"due", "missed"} and due_utc and _parse_stored(due_utc) > clock.now():
                    values["status"] = "scheduled"
                    values["snoozed_until"] = None
            if "rrule" in patch:
                if not allow_rrule:
                    raise ReminderError(409, "修改重复规则需要确认", "needs_confirmation")
                try:
                    anchor = _parse_stored(values.get("due_at", due_local))
                    rule = from_preset(patch.get("rrule"), anchor) if patch.get("rrule") else None
                    if rule:
                        rule = normalize(rule)
                except RRuleError as exc:
                    raise ReminderError(422, "不支持的重复规则") from exc
                if rule and not (values.get("due_at") if "due_at" in values else row.get("due_at")):
                    raise ReminderError(422, "无日期待办不能设置重复")
                values["rrule"] = rule
                detail["fields"].append("rrule")
        if "priority" in patch:
            values["priority"] = _check_priority(patch.get("priority"))
            detail["fields"].append("priority")
        if "assignee_bot_id" in patch:
            _require_bot(c, user_id, patch.get("assignee_bot_id"))
            values["assignee_bot_id"] = patch.get("assignee_bot_id")
            detail["fields"].append("assignee_bot_id")
        if "notify" in patch:
            notify = bool(patch.get("notify"))
            due_exists = values["due_at"] if "due_at" in values else row.get("due_at")
            values["notify"] = 1 if notify and due_exists else 0
            detail["fields"].append("notify")
        if "alert_offsets" in patch:
            values["alert_offsets"] = _check_offsets(patch.get("alert_offsets"))
            detail["fields"].append("alert_offsets")
        if not values:
            return to_public(row, names=_names_for(c, user_id, [row]))
        if "status" not in values:
            values["status"] = row["status"]
        return _apply(c, user_id, rid, expected_version=expected_version,
                      from_statuses=("scheduled", "due", "snoozed", "missed", "done"),
                      values=values, kind="updated", actor=actor, actor_bot_id=actor_bot_id, client=client,
                      detail=detail)


def complete_reminder(user_id: int, rid: int, *, actor="user", actor_bot_id=None, client="ios",
                      occurrence_due_utc=None) -> dict:
    now = clock.now()
    with db.tx() as c:
        row = _fetch(c, user_id, rid)
        if row is None:
            raise ReminderError(404, "提醒不存在")
        if occurrence_due_utc and row.get("due_utc") and occurrence_due_utc != row.get("due_utc"):
            # 重复提醒的某一次已经推进走了：视为这次已经处理过
            return to_public(row, names=_names_for(c, user_id, [row]))
        advanced = _advance_values(row, now)
        if advanced:
            advanced_public = _apply(
                c, user_id, rid, expected_version=row["version"],
                from_statuses=("scheduled", "due", "snoozed", "missed"), values=advanced,
                kind="completed", actor=actor, actor_bot_id=actor_bot_id, client=client,
                occurrence_due_utc=row.get("due_utc"), detail={"advanced": True})
            return advanced_public
        return _apply(
            c, user_id, rid, expected_version=row["version"],
            from_statuses=("scheduled", "due", "snoozed", "missed"),
            values={"status": "done", "completed_at": clock.iso_utc(now), "snoozed_until": None, "done": 1},
            kind="completed", actor=actor, actor_bot_id=actor_bot_id, client=client,
            occurrence_due_utc=row.get("due_utc"))


def snooze_reminder(user_id: int, rid: int, *, minutes: int | None = None, until: str | None = None,
                    actor="user", actor_bot_id=None, client="ios") -> dict:
    now = clock.now()
    if until:
        try:
            target = datetime.fromisoformat(until.replace("Z", "+00:00"))
        except ValueError:
            raise ReminderError(422, "时间格式无效，请使用 ISO8601") from None
        if target.tzinfo is None:
            target = target.replace(tzinfo=_tz(TIMEZONE))
    elif minutes is not None:
        try:
            minutes = int(minutes)
        except (TypeError, ValueError):
            raise ReminderError(422, "稍后时间无效") from None
        if minutes < 1 or minutes > 7 * 24 * 60:
            raise ReminderError(422, "稍后时间无效")
        target = now + timedelta(minutes=minutes)
    else:
        raise ReminderError(422, "请选择稍后时间")
    if target <= now:
        raise ReminderError(422, "不能把提醒设在过去")
    with db.tx() as c:
        row = _fetch(c, user_id, rid)
        if row is None:
            raise ReminderError(404, "提醒不存在")
        return _apply(
            c, user_id, rid, expected_version=row["version"],
            from_statuses=("scheduled", "due", "missed"),
            values={"status": "snoozed", "snoozed_until": clock.iso_utc(target)},
            kind="snoozed", actor=actor, actor_bot_id=actor_bot_id, client=client,
            detail={"snoozed_until": clock.iso_utc(target)})


def reopen_reminder(user_id: int, rid: int, *, actor="user", actor_bot_id=None, client="ios",
                    bot_limited=False) -> dict:
    now = clock.now()
    with db.tx() as c:
        row = _fetch(c, user_id, rid)
        if row is None:
            raise ReminderError(404, "提醒不存在")
        if bot_limited:
            done_at = _parse_stored(row.get("completed_at"))
            if done_at is None or now - done_at > GRACE:
                raise ReminderError(409, "只能在完成后 24 小时内撤销", "invalid_transition")
        due = _parse_stored(row.get("due_utc"))
        status = "scheduled" if due is None or due > now else "due"
        if due and now - due > GRACE and not row.get("rrule"):
            status = "missed"
        return _apply(
            c, user_id, rid, expected_version=row["version"], from_statuses=("done",),
            values={"status": status, "completed_at": None, "done": 0},
            kind="reopened", actor=actor, actor_bot_id=actor_bot_id, client=client)


def skip_reminder(user_id: int, rid: int, *, actor="user", actor_bot_id=None, client="ios") -> dict:
    now = clock.now()
    with db.tx() as c:
        row = _fetch(c, user_id, rid)
        if row is None:
            raise ReminderError(404, "提醒不存在")
        if not row.get("rrule"):
            raise ReminderError(409, "只有重复提醒可以跳过这一次", "invalid_transition")
        advanced = _advance_values(row, now)
        if not advanced:
            return _apply(
                c, user_id, rid, expected_version=row["version"],
                from_statuses=("scheduled", "due", "snoozed", "missed"),
                values={"status": "done", "completed_at": clock.iso_utc(now), "snoozed_until": None},
                kind="skipped", actor=actor, actor_bot_id=actor_bot_id, client=client,
                occurrence_due_utc=row.get("due_utc"), detail={"series_end": True})
        return _apply(
            c, user_id, rid, expected_version=row["version"],
            from_statuses=("scheduled", "due", "snoozed", "missed"), values=advanced,
            kind="skipped", actor=actor, actor_bot_id=actor_bot_id, client=client,
            occurrence_due_utc=row.get("due_utc"))


def cancel_reminder(user_id: int, rid: int, *, scope="series", actor="user", actor_bot_id=None, client="ios") -> dict:
    if scope == "occurrence":
        return skip_reminder(user_id, rid, actor=actor, actor_bot_id=actor_bot_id, client=client)
    now = clock.iso_utc(clock.now())
    with db.tx() as c:
        row = _fetch(c, user_id, rid)
        if row is None:
            raise ReminderError(404, "提醒不存在")
        return _apply(
            c, user_id, rid, expected_version=row["version"],
            from_statuses=("scheduled", "due", "snoozed", "missed", "done"),
            values={"status": "cancelled", "cancelled_at": now, "notify": 0},
            kind="cancelled", actor=actor, actor_bot_id=actor_bot_id, client=client,
            detail={"from": row["status"]})


def restore_reminder(user_id: int, rid: int, *, actor="user", client="ios") -> dict:
    now = clock.now()
    with db.tx() as c:
        row = _fetch(c, user_id, rid)
        if row is None:
            raise ReminderError(404, "提醒不存在")
        cancelled = _parse_stored(row.get("cancelled_at"))
        if row["status"] != "cancelled":
            _conflict(c, user_id, rid, "invalid_transition")
        if cancelled and now - cancelled > timedelta(days=KEEP_DAYS):
            raise ReminderError(409, "已超过 30 天，不能恢复", "invalid_transition")
        status = store.last_cancelled_from_status(c, user_id, rid) or "scheduled"
        if status not in {"scheduled", "due", "snoozed", "missed", "done"}:
            status = "scheduled"
        due = _parse_stored(row.get("due_utc"))
        if status != "done":
            if due is None:
                status = "scheduled"
            elif due > now:
                status = "scheduled"
            elif now - due > GRACE and not row.get("rrule"):
                status = "missed"
            else:
                status = "due"
        return _apply(
            c, user_id, rid, expected_version=row["version"], from_statuses=("cancelled",),
            values={"status": status, "cancelled_at": None, "notify": 1 if row.get("due_at") else 0},
            kind="restored", actor=actor, client=client, detail={"to": status})


def list_events(user_id: int, rid: int) -> dict:
    with db.tx() as c:
        if _fetch(c, user_id, rid) is None:
            raise ReminderError(404, "提醒不存在")
        rows = store.reminder_events(c, user_id, rid)
    for row in rows:
        row["detail"] = _loads(row.get("detail"), None)
    return {"events": rows}


def bot_visible(row, bot_id: int) -> bool:
    if row is None or row.get("status") == "cancelled":
        return False
    return row.get("bot_id") == bot_id or row.get("assignee_bot_id") == bot_id


def require_bot_row(user_id: int, bot_id: int, rid: int) -> dict:
    with db.tx() as c:
        row = _fetch(c, user_id, rid)
        if row is None or row.get("status") == "cancelled":
            raise ReminderError(404, "提醒不存在", "not_found")
        if not bot_visible(row, bot_id):
            raise ReminderError(404, "提醒不存在", "reminder_scope")
        return row


def find_duplicate(user_id: int, bot_id: int, title: str, due_utc: str | None) -> dict | None:
    with db.tx() as c:
        row = store.find_duplicate_reminder(c, user_id, bot_id, title, due_utc)
        if row is None:
            return None
        return to_public(row, names=_names_for(c, user_id, [row]))


def missed_occurrences(row, now: datetime) -> list[datetime]:
    """从当前 due 到 now（含）已经过去的次数。重复规则用墙上时间，不补发通知时用来计数。"""
    due = _local_due(row)
    rule = row.get("rrule")
    if due is None:
        stored = _parse_stored(row.get("due_utc"))
        return [stored] if stored and stored <= now else []
    if not rule:
        current = _parse_stored(row.get("due_utc")) or due
        return [current] if current <= now else []
    local_now = now.astimezone(due.tzinfo)
    occs = between(rule, due, due, local_now)
    cap = count_limit(rule)
    if cap is not None:
        index = int(row.get("occurrence_index") or 1)
        left = cap - index + 1
        occs = occs[:max(0, left)]
    return occs


def project_next_future(row, now: datetime) -> dict | None:
    """把重复提醒推到 now 之后的下一次。次数用尽或没有下一次时返回 None。"""
    rule = row.get("rrule")
    due = _local_due(row)
    if not rule or due is None:
        return None
    cap = count_limit(rule)
    index = int(row.get("occurrence_index") or 1)
    local_now = now.astimezone(due.tzinfo)
    nxt = next_after(rule, due, local_now)
    guard = 0
    while nxt is not None and guard < 500:
        guard += 1
        steps = len(between(rule, due, due, nxt))
        new_index = index + steps - 1
        if cap is not None and new_index > cap:
            return None
        if nxt.astimezone(ZoneInfo("UTC")) > now:
            return {
                "due_at": clock.iso_local(nxt),
                "due_utc": clock.iso_utc(nxt),
                "occurrence_index": new_index,
                "status": "scheduled",
                "snoozed_until": None,
                "completed_at": None,
            }
        nxt = next_after(rule, due, nxt)
    return None
