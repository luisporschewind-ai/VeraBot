"""v14 → v15：记忆主动建议。建议正文只存有界、安全的 JSON payload。"""

SUGGESTIONS_SCHEMA = """
CREATE TABLE IF NOT EXISTS suggestions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  bot_id INTEGER NOT NULL REFERENCES bots(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('routine_reminder','delegation')),
  dedupe_key TEXT NOT NULL CHECK (length(dedupe_key) BETWEEN 1 AND 160),
  payload TEXT NOT NULL CHECK (length(payload) <= 4096),
  status TEXT NOT NULL CHECK (status IN ('pending','accepted','dismissed','expired')),
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  decided_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_suggestions_user_bot_status_expiry
  ON suggestions(user_id, bot_id, status, expires_at);
CREATE INDEX IF NOT EXISTS idx_suggestions_cooldown
  ON suggestions(user_id, bot_id, kind, dedupe_key, status, decided_at);
CREATE UNIQUE INDEX IF NOT EXISTS idx_suggestions_active_dedupe
  ON suggestions(user_id, bot_id, kind, dedupe_key) WHERE status='pending';
"""


def migrate(c, ver: int) -> None:
    c.executescript(SUGGESTIONS_SCHEMA)
