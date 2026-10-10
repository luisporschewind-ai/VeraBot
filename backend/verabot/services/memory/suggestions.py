"""Detection and decisions for safe, user-confirmed suggestions."""
from __future__ import annotations

import hashlib
import json
import re
from datetime import date, datetime, time, timedelta, timezone
from difflib import SequenceMatcher
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from ... import db
from ...core.config import TIMEZONE
from ...db import reminder_store, suggestion_store
from ..reminders import service as reminder_service
from . import policy, repository as memory_repo

WEEKDAYS = {"一": "MO", "二": "TU", "三": "WE", "四": "TH", "五": "FR", "六": "SA", "日": "SU", "天": "SU"}
WEEKDAY_INDEX = {v: i for i, v in enumerate(("MO", "TU", "WE", "TH", "FR", "SA", "SU"))}
_WEEKDAY = re.compile(r"(?:每周|每星期|每个星期|每逢|周|星期)([一二三四五六日天])")
_TIME = re.compile(r"(早上|上午|中午|下午|晚上)?\s*(\d{1,2})\s*(?::|：|点|时)(\d{1,2})?\s*(?:分)?")


def _next_local(weekday: int, hour: int, minute: int, timezone_name: str, now: datetime | None = None) -> str:
    zone = ZoneInfo(timezone_name)
    now_local = (now or datetime.now(timezone.utc)).astimezone(zone)
    delta = (weekday - now_local.weekday()) % 7
    target_date = now_local.date() + timedelta(days=delta)
    target = datetime.combine(target_date, time(hour, minute), tzinfo=zone)
    if target <= now_local:
        target += timedelta(days=7)
    return target.isoformat(timespec="minutes")


def routine_schedule_from_text(text: str, timezone_name: str = TIMEZONE, now: datetime | None = None) -> dict | None:
    value = policy.clean(text)
    weekday_match, time_match = _WEEKDAY.search(value), _TIME.search(value)
    if not weekday_match or not time_match:
        return None
    day_code = WEEKDAYS[weekday_match.group(1)]
    hour = int(time_match.group(2))
    minute = int(time_match.group(3) or 0)
    period = time_match.group(1)
    if minute > 59 or hour > 24 or (hour == 24 and minute):
        return None
    if period in {"下午", "晚上"} and hour < 12:
        hour += 12
    elif period in {"早上", "上午"} and hour == 12:
        hour = 0
    elif period == "中午" and hour < 11:
        hour += 12
    try:
        due_at = _next_local(WEEKDAY_INDEX[day_code], hour % 24, minute, timezone_name, now)
    except (ZoneInfoNotFoundError, ValueError):
        return None
    title = _WEEKDAY.sub("", value)
    title = _TIME.sub("", title).strip(" ，,。.!！:：-—")
    title = re.sub(r"^(我)?(习惯|通常|一般会|会|每次)?\s*", "", title).strip()
    if not title:
        title = value[:200]
    return {"title": title[:200], "due_at": due_at, "timezone": timezone_name,
            "rrule": f"FREQ=WEEKLY;BYDAY={day_code}"}


def _title_key(text: str) -> str:
    return re.sub(r"[\W_]+", "", policy.clean(text).lower(), flags=re.UNICODE)


def detect_weekly_patterns(reminders: list[dict], *, now: datetime | None = None) -> list[dict]:
    """Find three similar one-off reminders on the same local weekday and time across distinct weeks."""
    cutoff = (now or datetime.now(timezone.utc)) - timedelta(days=21)
    groups: list[dict] = []
    for row in reminders:
        if row.get("status") not in {None, "scheduled", "due", "done"} or row.get("rrule"):
            continue
        title = policy.clean(str(row.get("title") or row.get("content") or ""))
        try:
            zone = ZoneInfo(row.get("timezone") or TIMEZONE)
            due = datetime.fromisoformat(str(row.get("due_at") or "").replace("Z", "+00:00"))
            if due.tzinfo is None:
                due = due.replace(tzinfo=zone)
            else:
                due = due.astimezone(zone)
            created = datetime.fromisoformat(str(row.get("created_at") or "").replace("Z", "+00:00"))
            if created.tzinfo is None:
                created = created.replace(tzinfo=timezone.utc)
            if created.astimezone(timezone.utc) < cutoff.astimezone(timezone.utc):
                continue
        except (TypeError, ValueError, ZoneInfoNotFoundError):
            continue
        code, sensitivity = policy.check(title, max_chars=200)
        if code or sensitivity != "normal" or not title:
            continue
        key = _title_key(title)
        for group in groups:
            if (group["timezone"] == zone.key and group["weekday"] == due.weekday()
                    and abs(group["minute_of_day"] - (due.hour * 60 + due.minute)) <= 30
                    and SequenceMatcher(None, key, group["key"]).ratio() >= 0.8):
                group["rows"].append((row, due))
                break
        else:
            groups.append({"key": key, "title": title, "timezone": zone.key, "weekday": due.weekday(),
                           "minute_of_day": due.hour * 60 + due.minute, "rows": [(row, due)]})
    out = []
    now_utc = now or datetime.now(timezone.utc)
    for group in groups:
        weeks = {due.isocalendar()[:2] for _, due in group["rows"]}
        if len(weeks) < 3:
            continue
        day = group["weekday"]
        due_at = _next_local(day, group["minute_of_day"] // 60, group["minute_of_day"] % 60,
                             group["timezone"], now_utc)
        out.append({"title": group["title"], "due_at": due_at, "timezone": group["timezone"],
                    "rrule": f"FREQ=WEEKLY;BYDAY={("MO", "TU", "WE", "TH", "FR", "SA", "SU")[day]}"})
    return out


def _key(kind: str, *parts) -> str:
    raw = "|".join(str(p) for p in parts)
    return f"{kind}:{hashlib.sha256(raw.encode()).hexdigest()[:40]}"


def _create(user_id: int, bot_id: int, kind: str, dedupe_key: str, payload: dict) -> dict:
    expires = (datetime.now(timezone.utc) + timedelta(days=30)).isoformat(timespec="seconds")
    return suggestion_store.create_or_get_active(user_id=user_id, bot_id=bot_id, kind=kind,
                                                dedupe_key=dedupe_key, payload=payload, expires_at=expires)


def _suggest_routines(user_id: int, bot: dict) -> None:
    access = bot.get("memory_access") or "none"
    if access == "none" or not memory_repo.user_enabled(user_id):
        return
    with db.tx() as c:
        memories = c.execute(
            "SELECT id,scope,content FROM memories WHERE user_id=? AND type='routine' AND status='active' "
            "AND ((scope='bot' AND bot_id=?) OR (scope='global' AND ?=1)) LIMIT 100",
            (user_id, bot["id"], int(access == "bot_and_global")),
        ).fetchall()
    for memory in memories:
        memory = dict(memory)
        schedule = routine_schedule_from_text(memory.get("content") or "", TIMEZONE)
        if not schedule:
            continue
        dedupe = _key("routine", memory["id"], schedule["rrule"], schedule["timezone"], schedule["due_at"][11:16])
        _create(user_id, bot["id"], "routine_reminder", dedupe, {**schedule, "source_memory_id": memory["id"]})


def _suggest_repeated_reminders(user_id: int, bot: dict) -> None:
    with db.tx() as c:
        reminders = [r for r in reminder_store.reminders_for_user(c, user_id)
                     if r.get("bot_id") == bot["id"]]
    for schedule in detect_weekly_patterns(reminders):
        dedupe = _key("reminder", _title_key(schedule["title"]), schedule["rrule"],
                      schedule["timezone"], schedule["due_at"][11:16])
        _create(user_id, bot["id"], "routine_reminder", dedupe, schedule)


def _suggest_delegations(user_id: int, bot: dict) -> None:
    cutoff = (datetime.now(timezone.utc) - timedelta(days=14)).isoformat()
    allowed = set(bot.get("delegate_to") or [])
    with db.tx() as c:
        rows = c.execute(
            "SELECT d.to_bot_id, COUNT(*) AS n, MAX(d.created_at) AS latest, b.name AS target_name "
            "FROM delegations d JOIN bots b ON b.id=d.to_bot_id AND b.user_id=d.user_id "
            "WHERE d.user_id=? AND d.from_bot_id=? AND d.created_at>=? "
            "GROUP BY d.to_bot_id HAVING COUNT(*)>=3",
            (user_id, bot["id"], cutoff),
        ).fetchall()
    for row in rows:
        target_id = int(row["to_bot_id"])
        if target_id in allowed:
            continue
        dedupe = _key("delegation", bot["id"], target_id)
        _create(user_id, bot["id"], "delegation", dedupe,
                {"source_bot_id": bot["id"], "target_bot_id": target_id, "target_name": row["target_name"],
                 "request_count": int(row["n"])})


def refresh_for_bot(user_id: int, bot: dict) -> None:
    _suggest_routines(user_id, bot)
    _suggest_repeated_reminders(user_id, bot)
    _suggest_delegations(user_id, bot)


def list_for_bot(user_id: int, bot: dict) -> list[dict]:
    refresh_for_bot(user_id, bot)
    safe = []
    for item in suggestion_store.list_pending(user_id, bot["id"]):
        try:
            payload = json.loads(item["payload"])
        except (TypeError, json.JSONDecodeError):
            payload = {}
        safe.append({"id": item["id"], "kind": item["kind"], "title": str(payload.get("title") or payload.get("target_name") or "").strip()[:200],
                     "created_at": item["created_at"], "expires_at": item["expires_at"]})
    return safe


def decide(user_id: int, suggestion_id: int, decision: str) -> dict | None:
    return suggestion_store.decide(user_id, suggestion_id, decision)


def accept(user_id: int, suggestion_id: int) -> dict | None:
    with db.tx() as c:
        c.execute("BEGIN IMMEDIATE")
        item = c.execute("SELECT * FROM suggestions WHERE id=? AND user_id=?", (suggestion_id, user_id)).fetchone()
        if not item:
            return None
        item = dict(item)
        try:
            payload = json.loads(item["payload"])
        except (TypeError, json.JSONDecodeError):
            payload = {}
        if item["status"] == "accepted":
            return {"status": "accepted", "kind": item["kind"],
                    "reminder_id": payload.get("created_reminder_id"),
                    "settings_bot_id": payload.get("source_bot_id") if item["kind"] == "delegation" else None,
                    "target_bot_id": payload.get("target_bot_id")}
        if item["status"] != "pending":
            return {"status": item["status"], "kind": item["kind"]}
        if datetime.fromisoformat(item["expires_at"].replace("Z", "+00:00")) <= datetime.now(timezone.utc):
            c.execute("UPDATE suggestions SET status='expired' WHERE id=? AND user_id=? AND status='pending'",
                      (suggestion_id, user_id))
            return {"status": "expired", "kind": item["kind"]}
        if payload.get("source_memory_id"):
            source = c.execute("SELECT 1 FROM memories WHERE id=? AND user_id=? AND status='active'",
                               (payload["source_memory_id"], user_id)).fetchone()
            if not source:
                c.execute("UPDATE suggestions SET status='expired' WHERE id=? AND user_id=?",
                          (suggestion_id, user_id))
                return {"status": "expired", "kind": item["kind"]}
        claimed = c.execute("UPDATE suggestions SET status='accepted',decided_at=? WHERE id=? AND user_id=? AND status='pending'",
                            (db.now_iso(), suggestion_id, user_id)).rowcount
        if claimed != 1:
            latest = c.execute("SELECT status FROM suggestions WHERE id=? AND user_id=?", (suggestion_id, user_id)).fetchone()
            return {"status": latest[0] if latest else "not_found", "kind": item["kind"]}
        result = {"status": "accepted", "kind": item["kind"]}
        if item["kind"] == "routine_reminder":
            reminder = reminder_service.create_reminder(
                user_id, title=str(payload.get("title") or "").strip(), due_at=payload.get("due_at"),
                timezone_name=payload.get("timezone") or TIMEZONE, rrule=payload.get("rrule"),
                bot_id=item["bot_id"], created_by="suggestion", client="ios", actor="user", _connection=c)
            reminder_id = int(reminder.get("id"))
            payload["created_reminder_id"] = reminder_id
            c.execute("UPDATE suggestions SET payload=? WHERE id=? AND user_id=?",
                      (json.dumps(payload, ensure_ascii=False), suggestion_id, user_id))
            result["reminder_id"] = reminder_id
        elif item["kind"] == "delegation":
            source_id, target_id = payload.get("source_bot_id"), payload.get("target_bot_id")
            valid = c.execute("SELECT 1 FROM bots WHERE id=? AND user_id=?", (source_id, user_id)).fetchone()
            target = c.execute("SELECT 1 FROM bots WHERE id=? AND user_id=?", (target_id, user_id)).fetchone()
            if not valid or not target:
                raise ValueError("suggestion_target_unavailable")
            result.update({"settings_bot_id": int(source_id), "target_bot_id": int(target_id)})
        return result
