"""v39: shared textual drift bottles, private encounters, memories and moderation.

Public contributions are append-only (sequence 1..50). Private encounters and
turns are tenant-scoped. Account deletion withdraws authored public text via a
trigger while private rows disappear through foreign-key cascades.
"""

STATEMENTS = (
    """CREATE TABLE IF NOT EXISTS drift_bottles(
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 origin_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
 origin_bot_id INTEGER REFERENCES bots(id) ON DELETE SET NULL,
 origin_bot_name TEXT NOT NULL DEFAULT '',
 origin_bot_avatar TEXT NOT NULL DEFAULT '🤖',
 origin_bot_color TEXT NOT NULL DEFAULT '#0F766E',
 state TEXT NOT NULL DEFAULT 'active' CHECK(state IN ('active','archived','empty')),
 public_count INTEGER NOT NULL DEFAULT 0 CHECK(public_count BETWEEN 0 AND 50),
 version INTEGER NOT NULL DEFAULT 1,
 created_at REAL NOT NULL,
 archived_at REAL,
 last_activity_at REAL NOT NULL
)""",
    "CREATE INDEX IF NOT EXISTS drift_bottles_match ON drift_bottles(state,public_count,last_activity_at)",
    """CREATE TABLE IF NOT EXISTS drift_bottle_contributions(
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 bottle_id INTEGER NOT NULL REFERENCES drift_bottles(id) ON DELETE CASCADE,
 author_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
 sequence INTEGER NOT NULL CHECK(sequence BETWEEN 1 AND 50),
 kind TEXT NOT NULL CHECK(kind IN ('origin','message')),
 body TEXT NOT NULL,
 state TEXT NOT NULL DEFAULT 'visible' CHECK(state IN ('visible','withdrawn','hidden')),
 authorship TEXT NOT NULL CHECK(authorship IN ('owner','coauthored','bot_draft')),
 bot_id INTEGER REFERENCES bots(id) ON DELETE SET NULL,
 bot_name TEXT NOT NULL,
 bot_avatar TEXT NOT NULL,
 bot_color TEXT NOT NULL DEFAULT '#0F766E',
 created_at REAL NOT NULL,
 withdrawn_at REAL,
 hidden_at REAL,
 UNIQUE(bottle_id,sequence)
)""",
    "CREATE INDEX IF NOT EXISTS drift_contrib_author ON drift_bottle_contributions(author_user_id)",
    "CREATE INDEX IF NOT EXISTS drift_contrib_bottle ON drift_bottle_contributions(bottle_id,state,sequence)",
    """CREATE TABLE IF NOT EXISTS drift_bottle_encounters(
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 bot_id INTEGER REFERENCES bots(id) ON DELETE SET NULL,
 bottle_id INTEGER NOT NULL REFERENCES drift_bottles(id) ON DELETE CASCADE,
 bot_name TEXT NOT NULL,
 bot_avatar TEXT NOT NULL,
 bot_color TEXT NOT NULL DEFAULT '#0F766E',
 lease_token TEXT NOT NULL UNIQUE,
 read_limit INTEGER NOT NULL DEFAULT 0,
 started_at REAL NOT NULL,
 expires_at REAL NOT NULL,
 ended_at REAL,
 end_reason TEXT CHECK(end_reason IN ('returned','released','expired')),
 version INTEGER NOT NULL DEFAULT 1,
 quiet INTEGER NOT NULL DEFAULT 0,
 last_activity_at REAL NOT NULL
)""",
    "CREATE UNIQUE INDEX IF NOT EXISTS drift_one_active_per_user ON drift_bottle_encounters(user_id) WHERE ended_at IS NULL",
    "CREATE UNIQUE INDEX IF NOT EXISTS drift_one_active_per_bottle ON drift_bottle_encounters(bottle_id) WHERE ended_at IS NULL",
    "CREATE INDEX IF NOT EXISTS drift_encounters_user ON drift_bottle_encounters(user_id,started_at DESC)",
    """CREATE TABLE IF NOT EXISTS drift_bottle_reads(
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 bottle_id INTEGER NOT NULL REFERENCES drift_bottles(id) ON DELETE CASCADE,
 encounter_id INTEGER,
 read_at REAL NOT NULL,
 PRIMARY KEY(user_id,bottle_id)
)""",
    """CREATE TABLE IF NOT EXISTS drift_bottle_turns(
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 encounter_id INTEGER NOT NULL REFERENCES drift_bottle_encounters(id) ON DELETE CASCADE,
 role TEXT NOT NULL CHECK(role IN ('user','bot','system')),
 kind TEXT NOT NULL CHECK(kind IN ('opening','chat','draft','quiet')),
 content TEXT NOT NULL,
 request_id TEXT,
 event_key TEXT,
 created_at REAL NOT NULL,
 visible INTEGER NOT NULL DEFAULT 1,
 UNIQUE(encounter_id,event_key)
)""",
    "CREATE INDEX IF NOT EXISTS drift_turns_encounter ON drift_bottle_turns(encounter_id,id)",
    """CREATE TABLE IF NOT EXISTS drift_bottle_memories(
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 encounter_id INTEGER NOT NULL UNIQUE REFERENCES drift_bottle_encounters(id) ON DELETE CASCADE,
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 title TEXT NOT NULL,
 summary TEXT NOT NULL,
 owner_note TEXT NOT NULL DEFAULT '',
 source_turn_ids TEXT NOT NULL DEFAULT '[]',
 source_contribution_ids TEXT NOT NULL DEFAULT '[]',
 generated_by TEXT NOT NULL CHECK(generated_by IN ('fact','bot')),
 owner_edited INTEGER NOT NULL DEFAULT 0,
 version INTEGER NOT NULL DEFAULT 1,
 created_at REAL NOT NULL,
 updated_at REAL NOT NULL
)""",
    """CREATE TABLE IF NOT EXISTS drift_bottle_operations(
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 request_id TEXT NOT NULL,
 kind TEXT NOT NULL,
 payload_hash TEXT NOT NULL,
 status TEXT NOT NULL CHECK(status IN ('pending','committed','failed')),
 result_json TEXT,
 error_json TEXT,
 created_at REAL NOT NULL,
 updated_at REAL NOT NULL,
 PRIMARY KEY(user_id,request_id)
)""",
    """CREATE TABLE IF NOT EXISTS drift_bottle_generation_locks(
 encounter_id INTEGER PRIMARY KEY REFERENCES drift_bottle_encounters(id) ON DELETE CASCADE,
 request_id TEXT NOT NULL,
 owner TEXT NOT NULL,
 updated_at REAL NOT NULL
)""",
    """CREATE TABLE IF NOT EXISTS drift_bottle_blocks(
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 blocked_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 created_at REAL NOT NULL,
 PRIMARY KEY(user_id,blocked_user_id)
)""",
    """CREATE TABLE IF NOT EXISTS drift_bottle_reports(
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 contribution_id INTEGER NOT NULL REFERENCES drift_bottle_contributions(id) ON DELETE CASCADE,
 reporter_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 reason TEXT NOT NULL,
 state TEXT NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','kept','hidden','restored')),
 created_at REAL NOT NULL,
 resolved_at REAL,
 resolved_by INTEGER
)""",
    "CREATE INDEX IF NOT EXISTS drift_reports_pending ON drift_bottle_reports(state,id)",
    """CREATE TABLE IF NOT EXISTS drift_bottle_report_hides(
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 contribution_id INTEGER NOT NULL REFERENCES drift_bottle_contributions(id) ON DELETE CASCADE,
 report_id INTEGER NOT NULL REFERENCES drift_bottle_reports(id) ON DELETE CASCADE,
 created_at REAL NOT NULL,
 PRIMARY KEY(user_id,contribution_id)
)""",
    """CREATE TABLE IF NOT EXISTS drift_bottle_moderation_actions(
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 report_id INTEGER NOT NULL REFERENCES drift_bottle_reports(id) ON DELETE CASCADE,
 admin_user_id INTEGER NOT NULL,
 action TEXT NOT NULL CHECK(action IN ('keep','hide','restore')),
 reason TEXT NOT NULL DEFAULT '',
 created_at REAL NOT NULL
)""",
    """CREATE TABLE IF NOT EXISTS drift_bottle_record_hides(
 user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 record_type TEXT NOT NULL CHECK(record_type IN ('encounter','release')),
 record_id INTEGER NOT NULL,
 hidden_at REAL NOT NULL,
 PRIMARY KEY(user_id,record_type,record_id)
)""",
    """CREATE TRIGGER IF NOT EXISTS drift_bottle_withdraw_on_user_delete
BEFORE DELETE ON users
BEGIN
 UPDATE drift_bottle_contributions
    SET state='withdrawn', body='', withdrawn_at=CAST(strftime('%s','now') AS REAL)
  WHERE author_user_id=OLD.id AND state!='withdrawn';
 UPDATE drift_bottles
    SET state='empty', version=version+1
  WHERE state='active'
    AND NOT EXISTS(SELECT 1 FROM drift_bottle_contributions c
                    WHERE c.bottle_id=drift_bottles.id AND c.state='visible');
END""",
)


def migrate(c, ver):
    for statement in STATEMENTS:
        c.execute(statement)
