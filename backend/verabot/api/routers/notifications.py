"""站内通知与偏好。"""
from zoneinfo import ZoneInfoNotFoundError

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel

from ...services.notify import dispatcher, prefs
from ..deps import current_user

router = APIRouter(tags=["notifications"])


class EventIn(BaseModel):
    event: str
    channel: str
    device_id: str | None = None
    at: str | None = None


class ReadAllIn(BaseModel):
    category: str | None = None
    before_id: int | None = None


class PrefsPatch(BaseModel):
    enabled: bool | None = None
    sound_enabled: bool | None = None
    categories: dict | None = None
    muted_bots: list[int] | None = None
    quiet_enabled: bool | None = None
    quiet_start: str | None = None
    quiet_end: str | None = None
    quiet_timezone: str | None = None
    preview: str | None = None


def _missing():
    raise HTTPException(404, "通知不存在")


@router.get("/api/notifications/summary")
def notification_summary(user=Depends(current_user)):
    return dispatcher.summary(user["id"])


@router.post("/api/notifications/read-all")
def notifications_read_all(body: ReadAllIn | None = None, user=Depends(current_user)):
    body = body or ReadAllIn()
    count = dispatcher.mark_all_read(user["id"], category=body.category, before_id=body.before_id)
    return {"ok": True, "updated": count}


@router.get("/api/notifications")
def notifications(user=Depends(current_user), unread: bool = False, category: str | None = None,
                  before_id: int | None = None, limit: int = 50):
    return dispatcher.list_notifications(user["id"], unread=unread, category=category, before_id=before_id, limit=limit)


@router.post("/api/notifications/{nid}/read")
def notification_read(nid: int, user=Depends(current_user)):
    row = dispatcher.mark_read(user["id"], nid, read=True)
    if not row:
        _missing()
    return row


@router.post("/api/notifications/{nid}/unread")
def notification_unread(nid: int, user=Depends(current_user)):
    row = dispatcher.mark_read(user["id"], nid, read=False)
    if not row:
        _missing()
    return row


@router.delete("/api/notifications/{nid}")
def notification_delete(nid: int, user=Depends(current_user)):
    if not dispatcher.delete_notification(user["id"], nid):
        _missing()
    return {"ok": True}


@router.post("/api/notifications/{nid}/events")
def notification_event(nid: int, body: EventIn, user=Depends(current_user)):
    try:
        result = dispatcher.report_event(user["id"], nid, event=body.event, channel=body.channel,
                                         device_id=body.device_id, at=body.at)
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from exc
    if not result:
        _missing()
    return result


@router.get("/api/notification-settings")
def notification_settings(user=Depends(current_user)):
    return prefs.get_prefs(user["id"])


@router.patch("/api/notification-settings")
def notification_settings_patch(body: PrefsPatch, user=Depends(current_user)):
    patch = body.model_dump(exclude_unset=True)
    try:
        return prefs.update_prefs(user["id"], patch)
    except ZoneInfoNotFoundError as exc:
        raise HTTPException(422, "时区无效") from exc
    except LookupError as exc:
        raise HTTPException(404, str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from exc


@router.get("/api/notification-events")
def notification_events(after: int | None = Query(None, ge=0), through: int | None = Query(None, ge=0),
                        limit: int = Query(100, ge=1, le=200), user=Depends(current_user)):
    from ...services.notify.events import list_events
    return list_events(user["id"], after=after, through=through, limit=limit)


class LocalStateIn(BaseModel):
    ids: list[int]


@router.post('/api/notifications/local-state')
def local_notification_state(body: LocalStateIn, user=Depends(current_user)):
    if len(body.ids) > 200 or any(n <= 0 for n in body.ids):
        raise HTTPException(422, '通知数量或标识无效')
    from ...services.notify.events import local_state
    return local_state(user['id'], body.ids)
