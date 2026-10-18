"""统一事项（Items）。账号隔离；写接口支持 Idempotency-Key。P1 不创建 Bot 任务。"""
import json
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from ...db import reminder_store
from ...services.items import service
from ...services.reminders import clock
from ...services.reminders import service as reminder_service
from ...services.reminders.service import ReminderError
from ..deps import current_user

router = APIRouter(tags=["items"])


class ChecklistIn(BaseModel):
    text: str
    done: bool = False


class ItemIn(BaseModel):
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
    checklist: list[ChecklistIn | str] | None = None
    source_kind: str | None = "manual"


class ItemPatch(BaseModel):
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
    source_kind: str | None = None


class ChecklistReplace(BaseModel):
    expected_version: int
    items: list[ChecklistIn | str]


class ChecklistPatch(BaseModel):
    done: bool | None = None


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


def _checklist_payload(entries):
    if entries is None:
        return None
    out = []
    for entry in entries:
        if isinstance(entry, str):
            out.append(entry)
        else:
            out.append({"text": entry.text, "done": entry.done})
    return out


@router.get("/api/items")
def items_list(user=Depends(current_user), view: str | None = None, bot_id: int | None = None,
               cursor: str | None = None, limit: int = 100):
    try:
        return service.list_items(user["id"], view=view, bot_id=bot_id, cursor=cursor, limit=limit)
    except ReminderError as exc:
        _raise(exc)


@router.post("/api/items")
def items_create(body: ItemIn, request: Request, user=Depends(current_user)):
    hit = _replay(user["id"], request)
    if hit:
        return JSONResponse(hit[1], status_code=hit[0])
    title = body.title or body.content or ""
    try:
        created = service.create_item(
            user["id"], title=title, note=body.note, due_at=body.due_at, timezone_name=body.timezone,
            all_day=body.all_day, rrule=body.rrule, priority=body.priority,
            assignee_bot_id=body.assignee_bot_id, source_message_id=body.source_message_id,
            notify=body.notify, alert_offsets=body.alert_offsets,
            checklist=_checklist_payload(body.checklist), source_kind=body.source_kind or "manual",
            client=_client(request), actor="user", created_by="user")
    except ReminderError as exc:
        _raise(exc)
    _idempotency_put(user["id"], request.headers.get("idempotency-key"), 201, created)
    return JSONResponse(created, status_code=201)


@router.get("/api/items/{rid}")
def items_get(rid: int, user=Depends(current_user)):
    try:
        return service.get_item(user["id"], rid)
    except ReminderError as exc:
        _raise(exc)


@router.patch("/api/items/{rid}")
def items_patch(rid: int, body: ItemPatch, request: Request, user=Depends(current_user)):
    hit = _replay(user["id"], request)
    if hit:
        return JSONResponse(hit[1], status_code=hit[0])
    patch = body.model_dump(exclude_unset=True)
    patch.pop("expected_version", None)
    try:
        updated = service.update_item(
            user["id"], rid, patch, expected_version=body.expected_version, actor="user",
            client=_client(request))
    except ReminderError as exc:
        _raise(exc)
    _idempotency_put(user["id"], request.headers.get("idempotency-key"), 200, updated)
    return updated


@router.post("/api/items/{rid}/complete")
def items_complete(rid: int, request: Request, user=Depends(current_user), body: CompleteIn | None = None):
    hit = _replay(user["id"], request)
    if hit:
        return JSONResponse(hit[1], status_code=hit[0])
    try:
        reminder_service.complete_reminder(
            user["id"], rid, actor="user", client=_client(request),
            occurrence_due_utc=(body.occurrence_due_utc if body else None))
        updated = service.get_item(user["id"], rid)
    except ReminderError as exc:
        _raise(exc)
    _idempotency_put(user["id"], request.headers.get("idempotency-key"), 200, updated)
    return updated


@router.post("/api/items/{rid}/reopen")
def items_reopen(rid: int, request: Request, user=Depends(current_user)):
    hit = _replay(user["id"], request)
    if hit:
        return JSONResponse(hit[1], status_code=hit[0])
    try:
        reminder_service.reopen_reminder(user["id"], rid, actor="user", client=_client(request))
        updated = service.get_item(user["id"], rid)
    except ReminderError as exc:
        _raise(exc)
    _idempotency_put(user["id"], request.headers.get("idempotency-key"), 200, updated)
    return updated


@router.post("/api/items/{rid}/snooze")
def items_snooze(rid: int, body: SnoozeIn, request: Request, user=Depends(current_user)):
    hit = _replay(user["id"], request)
    if hit:
        return JSONResponse(hit[1], status_code=hit[0])
    try:
        reminder_service.snooze_reminder(
            user["id"], rid, minutes=body.minutes, until=body.until, actor="user",
            client=_client(request))
        updated = service.get_item(user["id"], rid)
    except ReminderError as exc:
        _raise(exc)
    _idempotency_put(user["id"], request.headers.get("idempotency-key"), 200, updated)
    return updated


@router.post("/api/items/{rid}/skip")
def items_skip(rid: int, request: Request, user=Depends(current_user)):
    hit = _replay(user["id"], request)
    if hit:
        return JSONResponse(hit[1], status_code=hit[0])
    try:
        reminder_service.skip_reminder(user["id"], rid, actor="user", client=_client(request))
        updated = service.get_item(user["id"], rid)
    except ReminderError as exc:
        _raise(exc)
    _idempotency_put(user["id"], request.headers.get("idempotency-key"), 200, updated)
    return updated


@router.put("/api/items/{rid}/checklist")
def items_checklist_put(rid: int, body: ChecklistReplace, request: Request, user=Depends(current_user)):
    hit = _replay(user["id"], request)
    if hit:
        return JSONResponse(hit[1], status_code=hit[0])
    try:
        updated = service.replace_checklist(
            user["id"], rid, _checklist_payload(body.items), expected_version=body.expected_version)
    except ReminderError as exc:
        _raise(exc)
    _idempotency_put(user["id"], request.headers.get("idempotency-key"), 200, updated)
    return updated


@router.patch("/api/items/{rid}/checklist/{cid}")
def items_checklist_patch(rid: int, cid: int, body: ChecklistPatch | None = None, user=Depends(current_user)):
    try:
        return service.toggle_checklist(user["id"], rid, cid, done=(body.done if body else None))
    except ReminderError as exc:
        _raise(exc)
