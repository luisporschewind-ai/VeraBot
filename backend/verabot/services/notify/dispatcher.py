"""notify() 是通知的唯一入口：去重、偏好、免打扰、限流，然后写收件箱和投递记录。

R1 不创建 apns 投递。开了本地提醒的设备由自己排程，服务端只记 scheduled_local。
"""
from __future__ import annotations

import hashlib
import hmac
import logging
from datetime import datetime, timedelta

from ... import db
from ...core.config import JWT_SECRET
from ...db import reminder_store as store
from ..reminders import clock
from . import hub
from .devices import active_devices, token_log_ref
from .prefs import get_prefs, in_quiet_hours

log = logging.getLogger("verabot.notify")

BOT_MESSAGE_PER_BOT = 3
BOT_MESSAGE_PER_USER = 10
PLUGIN_PER_HOUR = 5
PLUGIN_PER_DAY = 20
APNS_PER_HOUR = 30
RANK = {
    "queued": 0, "scheduled_local": 1, "sent": 2, "delivered": 3, "opened": 4,
    "dismissed": 5, "suppressed": 5, "failed": 5, "expired": 5, "cancelled": 5,
}


def _day_start(now: datetime, tz_name: str) -> str:
    from zoneinfo import ZoneInfo
    local = now.astimezone(ZoneInfo(tz_name)).replace(hour=0, minute=0, second=0, microsecond=0)
    return clock.iso_utc(local)


def apply_preview(category: str, title: str, body: str | None, preview: str, sensitive: bool,
                  bot_name: str | None = None) -> tuple[str, str | None, bool]:
    """返回可展示的标题、正文，以及是否敏感。备注永远不进通知。"""
    if sensitive or preview == "none":
        return "你有一条新通知", None, True if sensitive else False
    if category == "bot_message" and preview != "full":
        name = bot_name or "助手"
        return f"「{name}」有新消息", None, False
    if preview == "title":
        return title, None, False
    return title, body, False


def push_payload(notification: dict, *, uid_hash: str) -> dict:
    """APNs 载荷（R3 才发送）。默认不带业务正文；sensitive 时标题也是通用文案。"""
    title = "你有一条新通知" if notification.get("sensitive") else (notification.get("title") or "Vera Bot")
    return {
        "aps": {"alert": {"title": title}, "sound": "default",
                "thread-id": notification.get("thread_id") or "verabot", "category": "VB_GENERIC"},
        "nid": notification["id"],
        "cat": notification["category"],
        "link": notification.get("link"),
        "uid": uid_hash,
    }


def uid_hash(user_id: int) -> str:
    return hmac.new(JWT_SECRET.encode(), str(user_id).encode(), hashlib.sha256).hexdigest()[:16]


def _limited(c, user_id: int, category: str, bot_id, plugin_id, now: datetime, tz_name: str) -> str | None:
    if category == "reminder":
        return None
    day = _day_start(now, tz_name)
    hour = clock.iso_utc(now - timedelta(hours=1))
    if category == "bot_message":
        per_user = store.count_notifications(c, user_id, "bot_message", day)
        if per_user >= BOT_MESSAGE_PER_USER:
            return "rate_user"
        if bot_id:
            per_bot = store.count_notifications(c, user_id, "bot_message", day, bot_id=bot_id)
            if per_bot >= BOT_MESSAGE_PER_BOT:
                return "rate_bot"
    if category == "plugin" and plugin_id:
        per_hour = store.count_notifications(c, user_id, "plugin", hour, plugin_id=plugin_id)
        if per_hour >= PLUGIN_PER_HOUR:
            return "rate_plugin_hour"
        per_day = store.count_notifications(c, user_id, "plugin", day, plugin_id=plugin_id)
        if per_day >= PLUGIN_PER_DAY:
            return "rate_plugin_day"
    return None


def _suppress_reason(prefs, category: str, *, bot_id, created_by, now, rate_reason) -> str | None:
    if rate_reason:
        return rate_reason
    if not prefs["enabled"]:
        return "disabled"
    if not prefs["categories"].get(category, False):
        return "category_off"
    if bot_id and bot_id in prefs["muted_bots"] and not (category == "reminder" and created_by == "user"):
        return "bot_muted"
    if category != "reminder" and category != "system" and in_quiet_hours(prefs, now):
        return "quiet_hours"
    return None


def notify(user_id: int, *, category: str, title: str, body: str | None = None, sensitive: bool = False,
           bot_id: int | None = None, reminder_id: int | None = None, message_id: int | None = None,
           plugin_id: str | None = None, link: str | None = None, thread_id: str | None = None,
           dedupe_key: str, created_by: str | None = None, conn=None) -> dict:
    if category not in {"reminder", "bot_message", "delegation", "plugin", "system"}:
        raise ValueError("未知通知分类")

    def work(c):
        existing = store.notification_by_dedupe(c, user_id, dedupe_key)
        if existing:
            return _public(existing), False
        prefs = get_prefs(user_id, conn=c)
        now = clock.now()
        bot_name = store.bot_name(c, user_id, bot_id) if bot_id else None
        shown_title, shown_body, force_sensitive = apply_preview(
            category, title, body, prefs["preview"], sensitive, bot_name)
        rate = _limited(c, user_id, category, bot_id, plugin_id, now, prefs["quiet_timezone"])
        reason = _suppress_reason(prefs, category, bot_id=bot_id, created_by=created_by, now=now, rate_reason=rate)
        created = clock.iso_utc(now)
        expires = clock.iso_utc(now + timedelta(days=30))
        nid = store.insert_notification(c, (
            user_id, category, shown_title, shown_body, 1 if (sensitive or force_sensitive) else 0,
            bot_id, reminder_id, message_id, plugin_id, link, thread_id, dedupe_key, created, expires,
        ))
        store.insert_inbox_delivery(c, nid, user_id, created)
        # R1 不发 APNs。本地提醒由设备自己排；这里只预置投递状态。提醒不限流。
        for device in active_devices(user_id, c):
            if category == "reminder" and device.get("local_reminders") and not reason:
                state, error = "scheduled_local", None
            elif category == "reminder" and device.get("local_reminders") and reason:
                state, error = "suppressed", reason
            else:
                state, error = ("suppressed", reason or "no_apns")
            if category != "reminder" and not device.get("local_reminders"):
                state, error = "suppressed", reason or "local_off"
            store.insert_local_delivery(c, nid, user_id, device["device_id"], state, error, created)
            if device.get("apns_token"):
                log.info("push device token …%s skipped (APNs not in R1)", token_log_ref(device.get("apns_token")))
        fresh = store.notification_by_id(c, nid)
        return _public(fresh), True

    if conn is not None:
        public, created = work(conn)
    else:
        with db.tx() as c:
            public, created = work(c)
    if created:
        hub.publish(user_id, {"id": public["id"], "category": public["category"], "title": public["title"],
                               "link": public.get("link")})
    return public


def _public(row: dict) -> dict:
    return {
        "id": row["id"],
        "category": row["category"],
        "title": row["title"],
        "body": row.get("body"),
        "sensitive": bool(row.get("sensitive")),
        "bot_id": row.get("bot_id"),
        "reminder_id": row.get("reminder_id"),
        "message_id": row.get("message_id"),
        "plugin_id": row.get("plugin_id"),
        "link": row.get("link"),
        "thread_id": row.get("thread_id"),
        "created_at": row.get("created_at"),
        "read_at": row.get("read_at"),
        "opened_at": row.get("opened_at"),
    }


def list_notifications(user_id: int, *, unread=False, category=None, before_id=None, limit=50) -> dict:
    limit = max(1, min(int(limit or 50), 200))
    with db.tx() as c:
        found = store.select_notifications(
            c, user_id, unread=unread, category=category, before_id=before_id, limit=limit)
        unread_count = store.unread_count(c, user_id)
    return {"notifications": [_public(r) for r in found], "unread_count": unread_count}


def summary(user_id: int) -> dict:
    with db.tx() as c:
        return {"unread_count": store.unread_count(c, user_id), "by_category": store.unread_by_category(c, user_id)}


def mark_read(user_id: int, nid: int, *, read: bool) -> dict:
    now = clock.iso_utc(clock.now())
    with db.tx() as c:
        found = store.notification_for_user(c, nid, user_id)
        if found is None:
            return {}
        if read and not found["read_at"]:
            store.set_notification_read(c, nid, user_id, now)
        elif not read and found["read_at"]:
            store.clear_notification_read(c, nid, user_id)
        fresh = store.notification_by_id(c, nid)
    return _public(fresh)


def mark_all_read(user_id: int, *, category=None, before_id=None) -> int:
    now = clock.iso_utc(clock.now())
    with db.tx() as c:
        return store.mark_notifications_read(c, user_id, now, category=category, before_id=before_id)


def delete_notification(user_id: int, nid: int) -> bool:
    with db.tx() as c:
        return store.delete_notification(c, nid, user_id) > 0


def report_event(user_id: int, nid: int, *, event: str, channel: str, device_id: str | None, at: str | None) -> dict:
    if event not in {"delivered", "opened", "dismissed"}:
        raise ValueError("事件无效")
    if channel not in {"inbox", "local", "apns"}:
        raise ValueError("渠道无效")
    when = at or clock.iso_utc(clock.now())
    with db.tx() as c:
        note = store.notification_for_user(c, nid, user_id)
        if note is None:
            return {}
        if event == "opened" and not note["opened_at"]:
            store.mark_notification_opened(c, nid, when)
        found = store.latest_delivery(c, nid, user_id, channel, device_id)
        state = event if event != "delivered" else "delivered"
        if found is None:
            store.insert_reported_delivery(
                c, nid, user_id, channel, device_id, state, when,
                when if event == "delivered" else None, when if event == "opened" else None)
        else:
            current = found["state"]
            if RANK.get(event, 0) >= RANK.get(current, 0) and current not in {"suppressed", "failed", "expired", "cancelled"}:
                delivered = found["delivered_at"] or (when if event in {"delivered", "opened"} else None)
                opened = found["opened_at"] or (when if event == "opened" else None)
                store.advance_delivery(c, state, when, delivered, opened, found["id"])
        fresh = store.latest_delivery_state(c, nid, user_id, channel)
    return {"ok": True, "state": fresh[0] if fresh else event}


def purge_old(now: datetime) -> None:
    cutoff = clock.iso_utc(now - timedelta(days=30))
    with db.tx() as c:
        store.purge_notifications(c, cutoff)


def delivery_rows(user_id: int, notification_id: int) -> list[dict]:
    with db.tx() as c:
        return store.deliveries_for(c, user_id, notification_id)
