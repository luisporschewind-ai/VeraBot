"""HTTP surface for Bot Drift Bottle. All routes require login."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query

from ..deps import current_user
from ...services.drift_bottle import service
from ...services.drift_bottle.contracts import (
    BlockRequest, BottleError, CreateBottleRequest, DraftSuggestionRequest, DrawRequest,
    MemoryPatch, MemoryRequest, ReleaseRequest, ReportRequest, TurnRequest, WithdrawRequest,
)

router = APIRouter(prefix="/api/games/drift-bottle", tags=["drift-bottle"])


def _call(fn, *args):
    try:
        return fn(*args)
    except BottleError as error:
        headers = {"Retry-After": str(error.retry_after)} if error.retry_after else None
        raise HTTPException(error.status, {"message": error.message, "code": error.code},
                            headers=headers) from error


@router.get("/state")
def state(user=Depends(current_user)):
    import time
    return _call(service.state, user["id"], time.time())


@router.post("/bottles")
def create_bottle(body: CreateBottleRequest, user=Depends(current_user)):
    import time
    return _call(service.create_bottle, user["id"], body, time.time())


@router.post("/draft-suggestions")
def draft_suggestion(body: DraftSuggestionRequest, user=Depends(current_user)):
    import time
    return _call(service.draft_suggestion, user["id"], body, time.time())


@router.post("/encounters")
def draw(body: DrawRequest, user=Depends(current_user)):
    import time
    return _call(service.draw, user["id"], body, time.time())


@router.get("/encounters/{encounter_id}")
def get_encounter(encounter_id: int, cursor: str | None = Query(default=None),
                  user=Depends(current_user)):
    import time
    return _call(service.get_encounter, user["id"], encounter_id, cursor, time.time())


@router.post("/encounters/{encounter_id}/turns")
def turns(encounter_id: int, body: TurnRequest, user=Depends(current_user)):
    import time
    return _call(service.turns, user["id"], encounter_id, body, time.time())


@router.post("/encounters/{encounter_id}/release")
def release(encounter_id: int, body: ReleaseRequest, user=Depends(current_user)):
    import time
    return _call(service.release, user["id"], encounter_id, body, time.time())


@router.post("/encounters/{encounter_id}/memory")
def generate_memory(encounter_id: int, body: MemoryRequest, user=Depends(current_user)):
    import time
    return _call(service.generate_memory, user["id"], encounter_id, body, time.time())


@router.get("/records")
def records(bot_id: int | None = Query(default=None, gt=0),
            cursor: str | None = Query(default=None),
            limit: int = Query(default=20, ge=1, le=50),
            user=Depends(current_user)):
    import time
    return _call(service.records, user["id"], bot_id, cursor, limit, time.time())


@router.get("/records/{record_id}")
def record(record_id: str, user=Depends(current_user)):
    import time
    return _call(service.record, user["id"], record_id, time.time())


@router.patch("/records/{record_id}/memory")
def patch_memory(record_id: str, body: MemoryPatch,
                 request_id: str = Query(..., min_length=8, max_length=128),
                 user=Depends(current_user)):
    import time
    return _call(service.patch_memory, user["id"], record_id, body, request_id, time.time())


@router.delete("/records/{record_id}/memory")
def delete_memory(record_id: str, request_id: str = Query(..., min_length=8, max_length=128),
                  user=Depends(current_user)):
    import time
    return _call(service.delete_memory, user["id"], record_id, request_id, time.time())


@router.delete("/records/{record_id}")
def delete_record(record_id: str, request_id: str = Query(..., min_length=8, max_length=128),
                  user=Depends(current_user)):
    import time
    return _call(service.delete_record, user["id"], record_id, request_id, time.time())


@router.post("/contributions/{contribution_id}/withdraw")
def withdraw(contribution_id: int, body: WithdrawRequest, user=Depends(current_user)):
    import time
    return _call(service.withdraw, user["id"], contribution_id, body, time.time())


@router.post("/reports")
def report(body: ReportRequest, user=Depends(current_user)):
    import time
    return _call(service.report, user["id"], body, time.time())


@router.post("/blocks")
def block(body: BlockRequest, user=Depends(current_user)):
    import time
    return _call(service.block, user["id"], body, time.time())


@router.get("/operations/{request_id}")
def operation(request_id: str, user=Depends(current_user)):
    import time
    return _call(service.operation, user["id"], request_id, time.time())
