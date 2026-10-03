"""用量看板（Quota）统计。"""
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from .. import db
from ..db import delegation_store, usage_store
from ..core.config import DEEPSEEK_MODEL, TIMEZONE


def compute_quota(user: dict) -> dict:
    """用量看板数据：今日 / 累计 / 7 日趋势 / 按 Bot / 委派次数 / 语音转写。"""
    tz = ZoneInfo(TIMEZONE)
    start_local = datetime.now(tz).replace(hour=0, minute=0, second=0, microsecond=0)
    start_utc = start_local.astimezone(timezone.utc).isoformat(timespec="seconds")
    week_utc = (start_local - timedelta(days=6)).astimezone(timezone.utc).isoformat(timespec="seconds")
    uid = user["id"]
    with db.tx() as c:
        total = usage_store.usage_totals(c, uid)
        today = usage_store.usage_totals(c, uid, start_utc)
        per_bot = usage_store.per_bot_usage(c, uid)
        daily_rows = usage_store.usage_since(c, uid, week_utc)
        delegations = delegation_store.count_for_user(c, uid)
        tr_total = usage_store.transcribe_totals(c, uid)
        tr_today = usage_store.transcribe_totals(c, uid, start_utc)
    daily = {(start_local - timedelta(days=i)).strftime("%m-%d"): 0 for i in range(6, -1, -1)}
    for r in daily_rows:
        k = datetime.fromisoformat(r["created_at"]).astimezone(tz).strftime("%m-%d")
        if k in daily:
            daily[k] += r["total_tokens"]
    _, budget = db.token_budget(user["id"])
    for row in per_bot:
        updated = row.pop("image_updated_at", None)
        row["has_avatar"] = bool(updated)
        row["avatar_updated_at"] = updated
    return {"model": DEEPSEEK_MODEL, "daily_token_quota": budget, "today": today, "total": total,
            "per_bot": per_bot, "daily": [{"date": k, "tokens": v} for k, v in daily.items()],
            "delegations": delegations,
            "transcribe": {"today": tr_today, "total": tr_total}}
