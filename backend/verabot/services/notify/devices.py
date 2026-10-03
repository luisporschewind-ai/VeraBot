"""设备注册。R1 只记录本地通知能力，不向 APNs 发任何请求。"""
from __future__ import annotations

from ... import db
from ...db import reminder_store as store
from ..reminders import clock


def register(user_id: int, body: dict) -> dict:
    device_id = str(body.get("device_id") or "").strip()
    if not device_id or len(device_id) > 80:
        raise ValueError("device_id 无效")
    platform = body.get("platform") or "ios"
    if platform not in {"ios"}:
        raise ValueError("平台无效")
    token = (body.get("apns_token") or None) or None
    if isinstance(token, str):
        token = token.strip() or None
    now = clock.iso_utc(clock.now())
    with db.tx() as c:
        if token:
            store.clear_apns_token_elsewhere(c, token, user_id, device_id)
        existing = store.device_by_ids(c, user_id, device_id)
        fields = {
            "platform": platform,
            "apns_token": token,
            "apns_env": body.get("apns_env"),
            "app_version": body.get("app_version"),
            "os_version": body.get("os_version"),
            "timezone": body.get("timezone"),
            "local_reminders": 1 if body.get("local_reminders", True) else 0,
            "disabled_at": None,
            "last_seen_at": now,
        }
        if existing:
            store.update_device(c, existing["id"], fields)
        else:
            store.insert_device(
                c, user_id, device_id, platform, token, body.get("apns_env"), body.get("app_version"),
                body.get("os_version"), body.get("timezone"), fields["local_reminders"], now,
            )
    return public_device(user_id, device_id)


def public_device(user_id: int, device_id: str) -> dict:
    with db.tx() as c:
        row = store.device_by_ids(c, user_id, device_id)
    if row is None:
        return {}
    return {
        "device_id": row["device_id"],
        "platform": row["platform"],
        "apns_token": row["apns_token"],
        "apns_env": row["apns_env"],
        "app_version": row["app_version"],
        "os_version": row["os_version"],
        "timezone": row["timezone"],
        "local_reminders": bool(row["local_reminders"]),
    }


def unregister(user_id: int, device_id: str) -> bool:
    now = clock.iso_utc(clock.now())
    with db.tx() as c:
        return store.unregister_device(c, now, user_id, device_id) > 0


def disable_user(user_id: int, conn=None) -> None:
    now = clock.iso_utc(clock.now())
    if conn is not None:
        store.disable_user_devices(conn, user_id, now)
        return
    with db.tx() as c:
        store.disable_user_devices(c, user_id, now)


def active_devices(user_id: int, conn) -> list[dict]:
    return store.active_devices(conn, user_id)


def token_log_ref(token: str | None) -> str:
    """日志里只留 token 后 6 位。"""
    if not token:
        return ""
    return token[-6:]
