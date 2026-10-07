"""提醒工具。Bot 只能看到、管理自己创建的和用户指派给它的提醒。"""
from datetime import datetime, timedelta
import re
from zoneinfo import ZoneInfo

from .. import db
from ..core.config import TIMEZONE
from ..services.reminders import clock, service
from ..services.reminders.rrule import RRuleError, from_preset
from ..services.reminders.service import ReminderError
from .registry import ToolContext, tool

WRITES_PER_TURN = 5


def _explicit_relative_due(user_text: str) -> str | None:
    """Resolve an explicit Chinese relative duration against the server clock."""
    match = re.search(r"([0-9零〇一二两三四五六七八九十]+)\s*(秒钟|秒|分钟|分|小时|钟头|天|日)\s*后", user_text)
    if not match:
        return None
    raw, unit = match.groups()
    if raw.isdigit():
        amount = int(raw)
    elif "十" in raw:
        tens, _, ones = raw.partition("十")
        digits = {"零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3,
                  "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9}
        amount = (digits[tens] if tens else 1) * 10 + (digits[ones] if ones else 0)
    else:
        digits = {"零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3,
                  "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9}
        amount = int("".join(str(digits[ch]) for ch in raw))
    if amount <= 0:
        return None
    seconds_per_unit = {"秒钟": 1, "秒": 1, "分钟": 60, "分": 60,
                        "小时": 3600, "钟头": 3600, "天": 86400, "日": 86400}
    target = clock.now().astimezone(ZoneInfo(TIMEZONE)) + timedelta(seconds=amount * seconds_per_unit[unit])
    # The reminder API has minute precision. Round up so a short duration never
    # becomes a timestamp in the past after dropping seconds.
    if target.second or target.microsecond:
        target = target.replace(second=0, microsecond=0) + timedelta(minutes=1)
    return target.isoformat(timespec="minutes")


def _human_when(rem: dict) -> str:
    if rem.get("repeat_label"):
        return rem["repeat_label"]
    raw = rem.get("due_at")
    if not raw:
        return "无日期"
    due = datetime.fromisoformat(raw)
    now = clock.now().astimezone(due.tzinfo or ZoneInfo(TIMEZONE))
    due_local = due.astimezone(now.tzinfo)
    if due_local.date() == now.date():
        day = "今天"
    elif due_local.date() == (now + timedelta(days=1)).date():
        day = "明天"
    else:
        day = f"{due_local.month}月{due_local.day}日"
    clock_text = "" if rem.get("all_day") else due_local.strftime(" %H:%M")
    if rem.get("all_day"):
        return f"{day} 全天"
    return f"{day}{clock_text}"


def _charge(ctx: ToolContext):
    ctx.turn.reminder_writes += 1
    if ctx.turn.reminder_writes > WRITES_PER_TURN:
        return {"error": "本轮提醒操作已达上限"}
    return None


def _scope(ctx: ToolContext, exc: ReminderError):
    if exc.code == "reminder_scope":
        db.audit(ctx.user_id, ctx.bot.get("id"), "tool_denied",
                 {"tool": "manage_reminder", "reason": "reminder_scope"})
    return {"error": "提醒不存在" if exc.status == 404 else exc.message}


@tool("create_reminder",
      "为用户创建一条提醒。先确认时间；due_at 用 ISO8601。没有明确时间就省略 due_at，建成无日期待办。不要重复创建。",
      {"type": "object", "properties": {
          "title": {"type": "string", "description": "提醒标题"},
          "content": {"type": "string", "description": "与 title 相同，兼容旧参数"},
          "note": {"type": "string", "description": "备注，可省略"},
          "due_at": {"type": "string", "description": "ISO8601 时间，可省略"},
          "repeat": {"type": "string", "description": "预设：每天、工作日、每周、每月、每年，或 RRULE"},
          "priority": {"type": "integer", "description": "0 无、1 低、2 中、3 高"}},
       "required": []})
async def create_reminder(ctx: ToolContext, title: str | None = None, content: str | None = None,
                          note: str | None = None, due_at: str | None = None, repeat: str | None = None,
                          priority: int | None = 0):
    text = (title or content or "").strip()
    if not text:
        return {"error": "请说明要提醒的内容"}
    key = None
    try:
        due_at = _explicit_relative_due(ctx.user_text) or due_at
        preview_due = None
        if due_at:
            try:
                preview_due = datetime.fromisoformat(due_at.replace("Z", "+00:00"))
            except ValueError:
                preview_due = None
        rule = from_preset(repeat, preview_due) if repeat else None
        due_utc = None
        if due_at:
            probe = service._build_when(due_at, TIMEZONE, False)
            due_utc = probe[1]
        key = (text[:200], due_utc or "")
    except ReminderError as exc:
        return {"error": exc.message}
    except RRuleError:
        return {"error": "不支持的重复规则"}
    except Exception:
        return {"error": "时间格式无效，请用 ISO8601，例如 2026-10-04T09:00+08:00"}
    cached = ctx.turn.reminder_created.get(key)
    if cached:
        return cached
    denied = _charge(ctx)
    if denied:
        return denied
    try:
        created = service.create_reminder(
            ctx.user_id, title=text, note=note, due_at=due_at, timezone_name=TIMEZONE, rrule=rule,
            priority=priority or 0, created_by="bot", bot_id=ctx.bot["id"], assignee_bot_id=ctx.bot["id"],
            source_message_id=ctx.user_message_id, client="chat", actor="bot", actor_bot_id=ctx.bot["id"])
    except ReminderError as exc:
        return {"error": exc.message}
    result = {"ok": True, "id": created["id"], "content": created["content"], "due_at": created["due_at"],
              "reminder": created, "summary": f"已创建提醒：{_human_when(created)} {created['title']}"}
    ctx.turn.reminder_created[key] = result
    return result


@tool("list_reminders", "列出这个 Bot 创建的、以及用户指派给它的未完成提醒。看不到其他 Bot 或用户自己的提醒。",
      {"type": "object", "properties": {
          "status": {"type": "string", "description": "状态，逗号分隔，可省略"},
          "range": {"type": "string", "description": "today、week 或 all"},
          "limit": {"type": "integer", "description": "最多 50 条"}}})
async def list_reminders(ctx: ToolContext, status: str | None = None, range: str | None = None, limit: int | None = None):
    start = end = None
    if range in {"today", "week"}:
        tz = ZoneInfo(TIMEZONE)
        begin = clock.now().astimezone(tz).replace(hour=0, minute=0, second=0, microsecond=0)
        start = clock.iso_utc(begin)
        end = clock.iso_utc(begin + timedelta(days=1 if range == "today" else 7))
    cap = min(int(limit or 50), 50)
    data = service.list_reminders(
        ctx.user_id, status=status or "scheduled,due,snoozed,missed", bot_id=ctx.bot["id"],
        start=start, end=end, limit=cap)
    # bot_id 过滤是「创建者或归属」。还要排除仅仅因为查询条件带上、但其实不是这个 Bot 的行——list 已按 bot 过滤。
    items = [{"id": r["id"], "content": r["title"], "title": r["title"], "due_at": r["due_at"],
              "status": r["status"], "repeat_label": r["repeat_label"]} for r in data["reminders"]]
    return {"count": len(items), "reminders": items,
            "summary": f"共 {len(items)} 条提醒"}


@tool("manage_reminder",
      "管理这个 Bot 自己的一条提醒：update、complete、snooze、reopen、skip。不能取消，也不能一次改多条。",
      {"type": "object", "properties": {
          "action": {"type": "string", "description": "update、complete、snooze、reopen、skip"},
          "id": {"type": "integer"},
          "title": {"type": "string"},
          "note": {"type": "string"},
          "due_at": {"type": "string"},
          "priority": {"type": "integer"},
          "minutes": {"type": "integer", "description": "稍后分钟数"},
          "until": {"type": "string", "description": "稍后到这个 ISO8601 时间"}},
       "required": ["action", "id"]})
async def manage_reminder(ctx: ToolContext, action: str, id: int | None = None, ids: list | None = None,
                          title: str | None = None, note: str | None = None, due_at: str | None = None,
                          priority: int | None = None, minutes: int | None = None, until: str | None = None,
                          rrule: str | None = None):
    if ids or action in {"cancel", "delete", "batch"}:
        return {"error": "取消、批量修改需要你在提醒页面确认，我不能直接做"}
    if rrule is not None:
        return {"error": "修改重复规则需要你确认，我不能直接改"}
    if id is None:
        return {"error": "请指定一条提醒"}
    try:
        service.require_bot_row(ctx.user_id, ctx.bot["id"], int(id))
    except ReminderError as exc:
        return _scope(ctx, exc)
    denied = _charge(ctx)
    if denied:
        return denied
    try:
        if action == "update":
            current = service.get_reminder(ctx.user_id, int(id))
            patch = {}
            if title is not None:
                patch["title"] = title
            if note is not None:
                patch["note"] = note
            if due_at is not None:
                patch["due_at"] = due_at
            if priority is not None:
                patch["priority"] = priority
            if not patch:
                return {"error": "没有要修改的内容"}
            updated = service.update_reminder(
                ctx.user_id, int(id), patch, expected_version=current["version"], actor="bot",
                actor_bot_id=ctx.bot["id"], client="chat", allow_rrule=False)
            summary = f"已更新提醒：{_human_when(updated)} {updated['title']}"
        elif action == "complete":
            updated = service.complete_reminder(ctx.user_id, int(id), actor="bot", actor_bot_id=ctx.bot["id"], client="chat")
            summary = f"已完成提醒：{updated['title']}"
        elif action == "snooze":
            updated = service.snooze_reminder(ctx.user_id, int(id), minutes=minutes, until=until, actor="bot",
                                             actor_bot_id=ctx.bot["id"], client="chat")
            summary = f"已稍后提醒：{updated['title']}"
        elif action == "reopen":
            updated = service.reopen_reminder(ctx.user_id, int(id), actor="bot", actor_bot_id=ctx.bot["id"],
                                             client="chat", bot_limited=True)
            summary = f"已恢复提醒：{updated['title']}"
        elif action == "skip":
            updated = service.skip_reminder(ctx.user_id, int(id), actor="bot", actor_bot_id=ctx.bot["id"], client="chat")
            summary = f"已跳过这一次：{updated['title']}"
        else:
            return {"error": "不支持的操作"}
    except ReminderError as exc:
        if exc.code == "reminder_scope":
            return _scope(ctx, exc)
        return {"error": exc.message}
    return {"ok": True, "id": updated["id"], "reminder": updated, "summary": summary}
