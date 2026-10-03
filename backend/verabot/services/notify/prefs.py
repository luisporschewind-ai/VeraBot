"""通知偏好。没有行时按默认值读，第一次 PATCH 才写入。"""
from __future__ import annotations

import json
from datetime import datetime
from zoneinfo import ZoneInfo

from ... import db
from ...core.config import TIMEZONE
from ...db import reminder_store as store
from ..reminders import clock

CATEGORIES = ("reminder", "bot_message", "delegation", "plugin", "system")
DEFAULT_CATEGORIES = {
    "reminder": True,
    "bot_message": True,
    "delegation": True,
    "plugin": False,
    "system": True,
}
PREVIEWS = ("full", "title", "none")


def _loads(text, default):
    try:
        value = json.loads(text) if text else default
    except (TypeError, ValueError):
        return default
    return value


def defaults() -> dict:
    return {
        "enabled": True,
        "categories": dict(DEFAULT_CATEGORIES),
        "muted_bots": [],
        "quiet_enabled": False,
        "quiet_start": "23:00",
        "quiet_end": "08:00",
        "quiet_timezone": TIMEZONE,
        "preview": "title",
    }


def _merge(row) -> dict:
    base = defaults()
    if row is None:
        return base
    cats = dict(DEFAULT_CATEGORIES)
    stored = _loads(row["categories"], {})
    if isinstance(stored, dict):
        for key, value in stored.items():
            if key in cats and key != "system":
                cats[key] = bool(value)
    cats["system"] = True
    muted = _loads(row["muted_bots"], [])
    if not isinstance(muted, list):
        muted = []
    base.update({
        "enabled": bool(row["enabled"]),
        "categories": cats,
        "muted_bots": [int(x) for x in muted if str(x).lstrip("-").isdigit()],
        "quiet_enabled": bool(row["quiet_enabled"]),
        "quiet_start": row["quiet_start"] or "23:00",
        "quiet_end": row["quiet_end"] or "08:00",
        "quiet_timezone": row["quiet_timezone"] or TIMEZONE,
        "preview": row["preview"] if row["preview"] in PREVIEWS else "title",
    })
    return base


def get_prefs(user_id: int, conn=None) -> dict:
    def read(c):
        return _merge(store.prefs_row(c, user_id))
    if conn is not None:
        return read(conn)
    with db.tx() as c:
        return read(c)


def _hhmm(text: str) -> str:
    parts = str(text).strip().split(":")
    if len(parts) != 2 or not all(p.isdigit() for p in parts):
        raise ValueError
    hour, minute = int(parts[0]), int(parts[1])
    if not (0 <= hour <= 23 and 0 <= minute <= 59):
        raise ValueError
    return f"{hour:02d}:{minute:02d}"


def update_prefs(user_id: int, patch: dict) -> dict:
    current = get_prefs(user_id)
    if "enabled" in patch:
        current["enabled"] = bool(patch["enabled"])
    if "categories" in patch and isinstance(patch["categories"], dict):
        for key, value in patch["categories"].items():
            if key == "system" and value is False:
                raise ValueError("系统安全通知不能关闭")
            if key in DEFAULT_CATEGORIES and key != "system":
                current["categories"][key] = bool(value)
    if "muted_bots" in patch:
        if not isinstance(patch["muted_bots"], list):
            raise ValueError("静音 Bot 列表无效")
        current["muted_bots"] = [int(x) for x in patch["muted_bots"]]
    if "quiet_enabled" in patch:
        current["quiet_enabled"] = bool(patch["quiet_enabled"])
    if "quiet_start" in patch:
        current["quiet_start"] = _hhmm(patch["quiet_start"])
    if "quiet_end" in patch:
        current["quiet_end"] = _hhmm(patch["quiet_end"])
    if "quiet_timezone" in patch:
        ZoneInfo(patch["quiet_timezone"])
        current["quiet_timezone"] = patch["quiet_timezone"]
    if "preview" in patch:
        if patch["preview"] not in PREVIEWS:
            raise ValueError("通知显示内容无效")
        current["preview"] = patch["preview"]
    now = clock.iso_utc(clock.now())
    with db.tx() as c:
        if "muted_bots" in patch:
            for bid in current["muted_bots"]:
                if not store.bot_exists(c, user_id, bid):
                    raise LookupError("Bot 不存在")
        store.upsert_prefs(
            c, user_id, 1 if current["enabled"] else 0, json.dumps(current["categories"], ensure_ascii=False),
            json.dumps(current["muted_bots"]), 1 if current["quiet_enabled"] else 0,
            current["quiet_start"], current["quiet_end"], current["quiet_timezone"], current["preview"], now,
        )
    return current


def _minutes(text: str) -> int:
    hour, minute = text.split(":")
    return int(hour) * 60 + int(minute)


def in_quiet_hours(prefs: dict, now: datetime) -> bool:
    if not prefs.get("quiet_enabled"):
        return False
    try:
        tz = ZoneInfo(prefs.get("quiet_timezone") or TIMEZONE)
        start = _minutes(prefs["quiet_start"])
        end = _minutes(prefs["quiet_end"])
    except Exception:
        return False
    if start == end:
        return False
    local = now.astimezone(tz)
    current = local.hour * 60 + local.minute
    if start < end:
        return start <= current < end
    return current >= start or current < end
