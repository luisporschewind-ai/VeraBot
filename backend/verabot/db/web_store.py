"""联网请求额度：预约写入现有审计账本，跨 worker 与重启共享。"""
from datetime import datetime, timezone

from .database import tx
from .repository import audit_in


def reserve_request(user_id: int, bot_id: int, operation: str, limit: int) -> bool:
    day = datetime.now(timezone.utc).date().isoformat()
    with tx(immediate=True) as c:
        used = c.execute(
            "SELECT count(*) FROM audit_log WHERE user_id=? AND kind='web_request' AND created_at>=?",
            (user_id, day),
        ).fetchone()[0]
        if used >= limit:
            return False
        audit_in(c, user_id, bot_id, "web_request", {"operation": operation})
        return True
