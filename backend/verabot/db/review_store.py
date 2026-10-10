"""Monthly review cache and account level review jobs."""
from .database import now_iso, row

def get(c, user_id: int, month: str):
    return row(c.execute("SELECT * FROM reviews WHERE user_id=? AND month=?", (user_id, month)).fetchone())

def start(c, user_id: int, month: str):
    now = now_iso()
    c.execute("INSERT OR IGNORE INTO reviews(user_id,month,status,content,created_at,updated_at) VALUES (?,?,'pending','{}',?,?)",
              (user_id, month, now, now))
    review = get(c, user_id, month)
    if review["status"] == "unavailable":
        c.execute("UPDATE reviews SET status='pending',updated_at=? WHERE id=?", (now, review["id"]))
        c.execute("UPDATE memory_jobs SET status='pending',attempts=0,error=NULL,finished_at=NULL WHERE user_id=? AND review_month=? AND kind='review' AND status IN ('done','failed','skipped')", (user_id,month))
    c.execute("INSERT OR IGNORE INTO memory_jobs(user_id,bot_id,kind,status,attempts,created_at,review_month) VALUES (?,NULL,'review','pending',0,?,?)",
              (user_id, now, month))
    return get(c, user_id, month)

def save(c, user_id: int, month: str, status: str, content: str, tokens: int = 0):
    c.execute("UPDATE reviews SET status=?,content=?,total_tokens=?,updated_at=? WHERE user_id=? AND month=?",
              (status, content, tokens, now_iso(), user_id, month))
