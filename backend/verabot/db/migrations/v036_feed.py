"""v36: independent personal Feed, durable fetch leases and per-user references."""
SCHEMA = '''
CREATE TABLE IF NOT EXISTS feed_plans(
 user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
 enabled INTEGER NOT NULL,bot_ids TEXT NOT NULL,topics TEXT NOT NULL,excluded_topics TEXT NOT NULL,
 use_memory INTEGER NOT NULL,version INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS feed_sources(
 id INTEGER PRIMARY KEY AUTOINCREMENT,user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 name TEXT NOT NULL,url TEXT NOT NULL,kind TEXT NOT NULL,bot_id INTEGER,
 enabled INTEGER NOT NULL DEFAULT 1,revision INTEGER NOT NULL DEFAULT 1,
 last_success_at TEXT,next_fetch_at TEXT,last_error TEXT,failure_count INTEGER NOT NULL DEFAULT 0,
 etag TEXT,modified TEXT,lease_token TEXT,lease_until TEXT);
CREATE UNIQUE INDEX IF NOT EXISTS feed_source_identity ON feed_sources(user_id,url,COALESCE(bot_id,0));
CREATE INDEX IF NOT EXISTS feed_source_due ON feed_sources(enabled,next_fetch_at,lease_until);
CREATE TABLE IF NOT EXISTS feed_items(
 id INTEGER PRIMARY KEY AUTOINCREMENT,user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 kind TEXT NOT NULL,title TEXT NOT NULL,url TEXT NOT NULL,author TEXT,
 source_id INTEGER NOT NULL REFERENCES feed_sources(id),published_at TEXT,created_at TEXT NOT NULL,
 summary TEXT NOT NULL,summary_basis TEXT NOT NULL,image_url TEXT,media_url TEXT,duration_seconds INTEGER,
 read INTEGER NOT NULL DEFAULT 0,saved INTEGER NOT NULL DEFAULT 0,dismissed INTEGER NOT NULL DEFAULT 0,
 UNIQUE(user_id,url));
CREATE INDEX IF NOT EXISTS feed_items_user ON feed_items(user_id,id);
CREATE INDEX IF NOT EXISTS feed_items_budget ON feed_items(user_id,created_at);
CREATE TABLE IF NOT EXISTS feed_pending_candidates(
 id INTEGER PRIMARY KEY AUTOINCREMENT,user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 source_id INTEGER NOT NULL REFERENCES feed_sources(id) ON DELETE CASCADE,
 url TEXT NOT NULL,payload TEXT NOT NULL,published_at TEXT,fetched_at TEXT NOT NULL,ordinal INTEGER NOT NULL,
 UNIQUE(user_id,source_id,url));
CREATE INDEX IF NOT EXISTS feed_pending_source ON feed_pending_candidates(user_id,source_id);
CREATE TABLE IF NOT EXISTS feed_item_recommendations(
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 item_id INTEGER NOT NULL REFERENCES feed_items(id) ON DELETE CASCADE,
 source_id INTEGER NOT NULL REFERENCES feed_sources(id) ON DELETE CASCADE,
 bot_id INTEGER,reason TEXT NOT NULL,
 PRIMARY KEY(item_id,source_id));
'''

def migrate(c, ver):
    for statement in SCHEMA.split(';'):
        if statement.strip(): c.execute(statement)
