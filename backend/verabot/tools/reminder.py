"""提醒工具：写入 / 查询 SQLite（MVP 不做推送）。"""
from datetime import datetime
from zoneinfo import ZoneInfo

from .. import db
from ..core.config import TIMEZONE
from .registry import ToolContext, tool


def _normalize_due(due_at: str | None) -> str | None:
    if not due_at:
        return None
    try:
        dt = datetime.fromisoformat(due_at.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=ZoneInfo(TIMEZONE))
        return dt.isoformat(timespec="minutes")
    except ValueError:
        return due_at  # 保留模型给出的原文，避免丢信息


@tool("create_reminder", "为用户创建一条提醒事项并保存。due_at 使用 ISO8601 本地时间，如 2026-09-30T09:00。",
      {"type": "object", "properties": {
          "content": {"type": "string", "description": "提醒内容"},
          "due_at": {"type": "string", "description": "提醒时间 ISO8601，可省略"}},
       "required": ["content"]})
async def create_reminder(ctx: ToolContext, content: str, due_at: str | None = None):
    due = _normalize_due(due_at)
    with db.tx() as c:
        rid = c.execute(
            "INSERT INTO reminders(user_id,bot_id,content,due_at,created_at) VALUES (?,?,?,?,?)",
            (ctx.user_id, ctx.bot["id"], content.strip()[:500], due, db.now_iso())).lastrowid
    return {"ok": True, "id": rid, "content": content, "due_at": due}


@tool("list_reminders", "列出当前用户尚未完成的提醒事项。",
      {"type": "object", "properties": {}})
async def list_reminders(ctx: ToolContext):
    with db.tx() as c:
        rs = db.rows(c.execute(
            "SELECT id, content, due_at FROM reminders WHERE user_id=? AND done=0 ORDER BY COALESCE(due_at,'9999'), id",
            (ctx.user_id,)).fetchall())
    return {"count": len(rs), "reminders": rs}
