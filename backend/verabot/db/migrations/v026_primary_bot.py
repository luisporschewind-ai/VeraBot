"""Account-scoped primary identity; choosing it never grants capabilities."""
def migrate(c, ver):
 c.execute('''CREATE TABLE IF NOT EXISTS primary_bot_settings (
 user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
 primary_bot_id INTEGER REFERENCES bots(id) ON DELETE SET NULL,
 active_enabled INTEGER NOT NULL DEFAULT 0 CHECK(active_enabled IN (0,1)),
 daily_token_limit INTEGER NOT NULL DEFAULT 20000 CHECK(daily_token_limit>0),
 version INTEGER NOT NULL DEFAULT 1)''')
