"""Protocol v2 endpoints for durable group inputs and observable execution."""
import asyncio
import json
from uuid import UUID

from fastapi import APIRouter, Depends, Header, HTTPException, Query, Request
from fastapi.responses import JSONResponse, StreamingResponse

from ..deps import current_user
from ..group_schemas import GroupInputIn, GroupTaskCommandIn
from .groups import require_group_v2
from ...db import group_execution_store as store
from ...services import group_dispatch, group_worker

router = APIRouter(prefix="/api/groups/{group_id}", tags=["group-execution"])


def _call(fn, *args, **kwargs):
    try:
        return fn(*args, **kwargs)
    except store.GroupExecutionError as exc:
        detail = {"code": exc.code, "message": exc.message}
        if exc.snapshot is not None:
            detail["task"] = exc.snapshot
        raise HTTPException(exc.status, detail) from exc


def _input_request(body: GroupInputIn, *, message: str | None = None):
    request = body.model_dump(mode="json")
    request["client_request_id"] = str(body.client_request_id)
    if message is not None:
        request["message"] = message
    return request


@router.post("/inputs", dependencies=[Depends(require_group_v2)])
def submit_input(group_id: int, body: GroupInputIn, user=Depends(current_user)):
    request = _input_request(body)
    prior = None
    try:
        prior = store.input_receipt(user["id"], group_id, request["client_request_id"])
    except store.GroupExecutionError as exc:
        if exc.status != 404:
            raise HTTPException(exc.status, {"code": exc.code, "message": exc.message}) from exc
    task = _call(group_dispatch.submit, user["id"], group_id, request)
    receipt = _call(store.input_receipt, user["id"], group_id, request["client_request_id"])
    response = {"task": task, "input_id": receipt["input_id"], "turn_id": receipt["turn_id"],
                "event_cursor": receipt["event_cursor"]}
    return JSONResponse(response, status_code=200 if prior else 202)


@router.get("/inputs/{client_request_id}")
def input_receipt(group_id: int, client_request_id: UUID, user=Depends(current_user)):
    return _call(store.input_receipt, user["id"], group_id, str(client_request_id))


@router.get("/execution")
def execution_snapshot(group_id: int, user=Depends(current_user)):
    return _call(store.execution_snapshot, user["id"], group_id)


@router.get("/events")
async def observe_events(group_id: int, request: Request, after_id: int = Query(default=0, ge=0),
                         last_event_id: str | None = Header(default=None, alias="Last-Event-ID"),
                         user=Depends(current_user)):
    _call(store.execution_snapshot, user["id"], group_id)
    if last_event_id is not None:
        try:
            after_id = max(after_id, int(last_event_id))
        except ValueError:
            raise HTTPException(400, {"code": "invalid_event_cursor", "message": "事件游标无效"})

    async def stream():
        cursor = after_id
        while not await request.is_disconnected():
            rows = _call(store.events, user["id"], group_id, cursor, 100)
            if rows:
                for event in rows:
                    cursor = event["id"]
                    yield f"id: {cursor}\nevent: {event['kind']}\ndata: {json.dumps(event, ensure_ascii=False)}\n\n"
                continue
            state = _call(store.execution_snapshot, user["id"], group_id,include_messages=False)
            task = state["task"]
            if task is None or task["state"] in {"awaiting_user", "completed", "stopped", "failed", "interrupted"}:
                break
            yield ": heartbeat\n\n"
            await asyncio.sleep(0.5)

    return StreamingResponse(stream(), media_type="text/event-stream",
                             headers={"X-Accel-Buffering": "no", "Cache-Control": "no-store"})


@router.post("/tasks/{task_id}/stop", dependencies=[Depends(require_group_v2)])
def stop_task(group_id: int, task_id: int, body: GroupTaskCommandIn, user=Depends(current_user)):
    task = _call(store.stop, user["id"], group_id, task_id, body.expected_version)
    group_worker.request_cancel(task_id)
    return task


@router.post("/tasks/{task_id}/resume", dependencies=[Depends(require_group_v2)])
def resume_task(group_id: int, task_id: int, body: GroupTaskCommandIn, user=Depends(current_user)):
    try:
        existing=store.input_receipt(user["id"],group_id,str(body.client_request_id))
        return JSONResponse(existing["task"],status_code=200)
    except store.GroupExecutionError as exc:
        if exc.status != 404:
            raise HTTPException(exc.status,{"code":exc.code,"message":exc.message})
    prior = _call(store.snapshot, user["id"], group_id, task_id)
    if prior is None:
        raise HTTPException(404, {"code": "not_found", "message": "群任务不存在"})
    if prior["version"] != body.expected_version or prior["state"] not in {"interrupted", "failed", "stopped"}:
        raise HTTPException(409, {"code": "task_version_changed", "message": "当前任务不能继续", "task": prior})
    message = body.message.strip() or f"继续处理：{prior['goal']}"
    request = {"client_request_id": str(body.client_request_id), "message": message,
               "target_member_ids": [], "everyone": False, "reply_to_message_id": None,
               "attachment_ids": [], "expected_task_id": task_id, "expected_version":body.expected_version,
               "clarification_id": None,"resume_task_id":task_id}
    task = _call(group_dispatch.submit, user["id"], group_id, request)
    return JSONResponse(task, status_code=202)


@router.post("/messages/{message_id}/retry-v2", dependencies=[Depends(require_group_v2)])
def retry_step(group_id: int, message_id: int, body: GroupTaskCommandIn, user=Depends(current_user)):
    task = _call(store.retry_failed, user["id"], group_id, message_id,
                 str(body.client_request_id), body.expected_version)
    return JSONResponse(task, status_code=202)
