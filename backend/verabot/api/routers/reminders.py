"""提醒（Reminders）。账号隔离；写接口支持 Idempotency-Key。"""
import json
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from ...db import reminder_store
from ...services.reminders import clock, service
from ...services.reminders.service import ReminderError
from ..deps import current_user

router = APIRouter(tags=["reminders"])


class ReminderIn(BaseModel):
    title: str | None = None
    content: str | None = None
    note: str | None = None
    due_at: str | None = None
    timezone: str | None = None
    all_day: bool = False
    rrule: str | None = None
    priority: int = 0
    assignee_bot_id: int | None = None
    source_message_id: int | None = None
    notify: bool | None = None
    alert_offsets: list[int] | None = None


class ReminderPatch(BaseModel):
    expected_version: int
    title: str | None = None
    note: str | None = None
    due_at: str | None = None
    timezone: str | None = None
    all_day: bool | None = None
    rrule: str | None = None
    priority: int | None = None
    assignee_bot_id: int | None = None
    notify: bool | None = None
    alert_offsets: list[int] | None = None


class CompleteIn(BaseModel):
    occurrence_due_utc: str | None = None


class SnoozeIn(BaseModel):
    minutes: int | None = None
    until: str | None = None


def _raise(exc: ReminderError):
    if exc.code or exc.reminder is not None:
        raise HTTPException(exc.status, {"message": exc.message, "code": exc.code, "reminder": exc.reminder})
    raise HTTPException(exc.status, exc.message)


def _client(request: Request) -> str:
    raw = (request.headers.get("x-verabot-client") or "").lower()
    if raw in {"ios", "web", "chat", "notification"}:
        return raw
    return "web"


def _idempotency_get(user_id: int, key: str | None):
    if not key:
        return None
    row = reminder_store.get_idempotency(user_id, key)
    if row is None:
        return None
    created = datetime.fromisoformat(row["created_at"])
    if clock.now() - created > timedelta(hours=24):
        return None
    return row["status_code"], json.loads(row["body"])


def _idempotency_put(user_id: int, key: str | None, status: int, body: dict):
    if not key:
        return
    reminder_store.put_idempotency(
        user_id, key, status, json.dumps(body, ensure_ascii=False), clock.iso_utc(clock.now()))


def _replay(user_id: int, request: Request):
    return _idempotency_get(user_id, request.headers.get("idempotency-key"))


@router.get("/api/reminders")
def reminders(request: Request, user=Depends(current_user), status: str | None = None, bot_id: int | None = None,
              created_by: str | None = None, from_: str | None = None, to: str | None = None,
              updated_since: str | None = None, limit: int = 200, before_id: int | None = None):
    # 查询参数 from 是 Python 关键字，OpenAPI 名仍用 from
    start = request.query_params.get("from") or from_
    try:
        return service.list_reminders(user["id"], status=status, bot_id=bot_id, created_by=created_by,
                                      start=start, end=to, updated_since=updated_since, limit=limit,
                                      before_id=before_id)
    except ReminderError as exc:
        _raise(exc)


@router.post("/api/reminders")
def create_reminder(body: ReminderIn, request: Request, user=Depends(current_user)):
    hit = _replay(user["id"], request)
    if hit:
        return JSONResponse(hit[1], status_code=hit[0])
    title = body.title or body.content or ""
    try:
        created = service.create_reminder(
            user["id"], title=title, note=body.note, due_at=body.due_at, timezone_name=body.timezone,
            all_day=body.all_day, rrule=body.rrule, priority=body.priority, assignee_bot_id=body.assignee_bot_id,
            source_message_id=body.source_message_id, notify=body.notify, alert_offsets=body.alert_offsets,
            created_by="user", client=_client(request), actor="user")
    except ReminderError as exc:
        _raise(exc)
    _idempotency_put(user["id"], request.headers.get("idempotency-key"), 201, created)
    return JSONResponse(created, status_code=201)


@router.get("/api/reminders/{rid}")
def reminder_get(rid: int, user=Depends(current_user)):
    try:
        return service.get_reminder(user["id"], rid)
    except ReminderError as exc:
        _raise(exc)


@router.patch("/api/reminders/{rid}")
def reminder_patch(rid: int, body: ReminderPatch, request: Request, user=Depends(current_user)):
    hit = _replay(user["id"], request)
    if hit:
        return JSONResponse(hit[1], status_code=hit[0])
    patch = body.model_dump(exclude_unset=True)
    patch.pop("expected_version", None)
    try:
        updated = service.update_reminder(user["id"], rid, patch, expected_version=body.expected_version,
                                          actor="user", client=_client(request))
    except ReminderError as exc:
        _raise(exc)
    _idempotency_put(user["id"], request.headers.get("idempotency-key"), 200, updated)
    return updated


@router.post("/api/reminders/{rid}/complete")
def reminder_complete(rid: int, request: Request, user=Depends(current_user), body: CompleteIn | None = None):
    hit = _replay(user["id"], request)
    if hit:
        return JSONResponse(hit[1], status_code=hit[0])
    try:
        updated = service.complete_reminder(user["id"], rid, actor="user", client=_client(request),
                                            occurrence_due_utc=(body.occurrence_due_utc if body else None))
    except ReminderError as exc:
        _raise(exc)
    _idempotency_put(user["id"], request.headers.get("idempotency-key"), 200, updated)
    return updated


@router.post("/api/reminders/{rid}/done")
def reminder_done(rid: int, user=Depends(current_user)):
    """旧接口。Web 仍用它标记完成；已经完成时再点一次也返回成功。"""
    try:
        current = service.get_reminder(user["id"], rid)
    except ReminderError as exc:
        _raise(exc)
    if current["status"] == "done":
        return {"ok": True}
    try:
        service.complete_reminder(user["id"], rid, actor="user", client="web")
    except ReminderError as exc:
        _raise(exc)
    return {"ok": True}


@router.post("/api/reminders/{rid}/snooze")
def reminder_snooze(rid: int, body: SnoozeIn, request: Request, user=Depends(current_user)):
    hit = _replay(user["id"], request)
    if hit:
        return JSONResponse(hit[1], status_code=hit[0])
    try:
        updated = service.snooze_reminder(user["id"], rid, minutes=body.minutes, until=body.until,
                                          actor="user", client=_client(request))
    except ReminderError as exc:
        _raise(exc)
    _idempotency_put(user["id"], request.headers.get("idempotency-key"), 200, updated)
    return updated


@router.post("/api/reminders/{rid}/reopen")
def reminder_reopen(rid: int, request: Request, user=Depends(current_user)):
    hit = _replay(user["id"], request)
    if hit:
        return JSONResponse(hit[1], status_code=hit[0])
    try:
        updated = service.reopen_reminder(user["id"], rid, actor="user", client=_client(request))
    except ReminderError as exc:
        _raise(exc)
    _idempotency_put(user["id"], request.headers.get("idempotency-key"), 200, updated)
    return updated


@router.post("/api/reminders/{rid}/skip")
def reminder_skip(rid: int, request: Request, user=Depends(current_user)):
    hit = _replay(user["id"], request)
    if hit:
        return JSONResponse(hit[1], status_code=hit[0])
    try:
        updated = service.skip_reminder(user["id"], rid, actor="user", client=_client(request))
    except ReminderError as exc:
        _raise(exc)
    _idempotency_put(user["id"], request.headers.get("idempotency-key"), 200, updated)
    return updated


@router.post("/api/reminders/{rid}/restore")
def reminder_restore(rid: int, request: Request, user=Depends(current_user)):
    hit = _replay(user["id"], request)
    if hit:
        return JSONResponse(hit[1], status_code=hit[0])
    try:
        updated = service.restore_reminder(user["id"], rid, actor="user", client=_client(request))
    except ReminderError as exc:
        _raise(exc)
    _idempotency_put(user["id"], request.headers.get("idempotency-key"), 200, updated)
    return updated


@router.delete("/api/reminders/{rid}")
def reminder_delete(rid: int, request: Request, user=Depends(current_user), scope: str = "series"):
    hit = _replay(user["id"], request)
    if hit:
        return JSONResponse(hit[1], status_code=hit[0])
    try:
        updated = service.cancel_reminder(user["id"], rid, scope=scope, actor="user", client=_client(request))
    except ReminderError as exc:
        _raise(exc)
    _idempotency_put(user["id"], request.headers.get("idempotency-key"), 200, updated)
    return updated


@router.get("/api/reminders/{rid}/events")
def reminder_events(rid: int, user=Depends(current_user)):
    try:
        return service.list_events(user["id"], rid)
    except ReminderError as exc:
        _raise(exc)
