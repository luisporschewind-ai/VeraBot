"""Preserve call identity after group deletion; event cursors never repeat after clear."""
from .v024_group_execution import SCHEMA


def migrate(c, ver: int) -> None:
    if ver >= 25:
        return
    for name in ("chat_group_events", "chat_group_usage_calls"):
        definition = next(s.strip() for s in SCHEMA.split(";") if s.strip().startswith(f"CREATE TABLE IF NOT EXISTS {name} ("))
        definition = definition.replace(f"IF NOT EXISTS {name}", f"IF NOT EXISTS {name}_v25")
        if name == "chat_group_events":
            definition = definition.replace("id INTEGER PRIMARY KEY,", "id INTEGER PRIMARY KEY AUTOINCREMENT,")
        else:
            definition = definition.replace("group_id INTEGER NOT NULL REFERENCES chat_groups(id) ON DELETE CASCADE", "group_id INTEGER REFERENCES chat_groups(id) ON DELETE SET NULL")
        c.execute(definition)
        columns = ",".join(row[1] for row in c.execute(f"PRAGMA table_info({name})"))
        c.execute(f"INSERT INTO {name}_v25({columns}) SELECT {columns} FROM {name}")
        c.execute(f"DROP TABLE {name}")
        c.execute(f"ALTER TABLE {name}_v25 RENAME TO {name}")
    c.execute("CREATE INDEX IF NOT EXISTS idx_group_events_cursor ON chat_group_events(group_id,id)")
