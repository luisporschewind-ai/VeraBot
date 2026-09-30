"""提醒（Reminders）。"""
from fastapi import APIRouter, Depends, HTTPException

from ... import db
from ..deps import current_user

router = APIRouter(tags=["reminders"])


@router.get("/api/reminders")
def reminders(user=Depends(current_user)):
    with db.tx() as c:
        rs = db.rows(c.execute("SELECT r.id, r.content, r.due_at, r.done, r.created_at, b.name AS bot_name "
                               "FROM reminders r LEFT JOIN bots b ON b.id=r.bot_id WHERE r.user_id=? "
                               "ORDER BY r.done, COALESCE(r.due_at,'9999'), r.id", (user["id"],)).fetchall())
    return {"reminders": rs}


@router.post("/api/reminders/{rid}/done")
def reminder_done(rid: int, user=Depends(current_user)):
    with db.tx() as c:
        n = c.execute("UPDATE reminders SET done=1 WHERE id=? AND user_id=?", (rid, user["id"])).rowcount
    if not n:
        raise HTTPException(404, "提醒不存在")
    return {"ok": True}
