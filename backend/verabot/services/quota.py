"""用量看板（Quota）统计。"""
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from .. import db
from ..core.config import DEEPSEEK_MODEL, TIMEZONE


def compute_quota(user: dict) -> dict:
    """用量看板数据：今日 / 累计 / 7 日趋势 / 按 Bot / 委派次数 / 语音转写。"""
    tz = ZoneInfo(TIMEZONE)
    start_local = datetime.now(tz).replace(hour=0, minute=0, second=0, microsecond=0)
    start_utc = start_local.astimezone(timezone.utc).isoformat(timespec="seconds")
    week_utc = (start_local - timedelta(days=6)).astimezone(timezone.utc).isoformat(timespec="seconds")
    q = ("SELECT COUNT(*) AS requests, COALESCE(SUM(prompt_tokens),0) AS prompt_tokens, "
         "COALESCE(SUM(completion_tokens),0) AS completion_tokens, COALESCE(SUM(total_tokens),0) AS total_tokens "
         "FROM usage_log WHERE user_id=?")
    with db.tx() as c:
        total = db.row(c.execute(q, (user["id"],)).fetchone())
        today = db.row(c.execute(q + " AND created_at>=?", (user["id"], start_utc)).fetchone())
        per_bot = db.rows(c.execute(
            "SELECT b.id, b.name, b.avatar, b.color, COUNT(u.id) AS requests, COALESCE(SUM(u.total_tokens),0) AS "
            "total_tokens FROM bots b LEFT JOIN usage_log u ON u.bot_id=b.id AND u.user_id=b.user_id "
            "WHERE b.user_id=? GROUP BY b.id ORDER BY total_tokens DESC", (user["id"],)).fetchall())
        daily_rows = c.execute("SELECT created_at, total_tokens FROM usage_log WHERE user_id=? AND created_at>=?",
                               (user["id"], week_utc)).fetchall()
        delegations = c.execute("SELECT COUNT(*) FROM delegations WHERE user_id=?", (user["id"],)).fetchone()[0]
        tq = ("SELECT COUNT(*) AS requests, COALESCE(SUM(duration_s),0) AS seconds, COALESCE(SUM(chars),0) AS chars "
              "FROM transcriptions WHERE user_id=?")
        tr_total = db.row(c.execute(tq, (user["id"],)).fetchone())
        tr_today = db.row(c.execute(tq + " AND created_at>=?", (user["id"], start_utc)).fetchone())
    daily = {(start_local - timedelta(days=i)).strftime("%m-%d"): 0 for i in range(6, -1, -1)}
    for r in daily_rows:
        k = datetime.fromisoformat(r["created_at"]).astimezone(tz).strftime("%m-%d")
        if k in daily:
            daily[k] += r["total_tokens"]
    _, budget = db.token_budget(user["id"])
    return {"model": DEEPSEEK_MODEL, "daily_token_quota": budget, "today": today, "total": total,
            "per_bot": per_bot, "daily": [{"date": k, "tokens": v} for k, v in daily.items()],
            "delegations": delegations,
            "transcribe": {"today": tr_today, "total": tr_total}}
