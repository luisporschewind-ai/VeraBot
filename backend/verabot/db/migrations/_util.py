"""迁移共用的小工具：查列 / 幂等加列。"""


def _columns(c, table: str) -> set[str]:
    return {r[1] for r in c.execute(f"PRAGMA table_info({table})").fetchall()}


def _add_column(c, table: str, name: str, ddl: str):
    if name not in _columns(c, table):
        c.execute(f"ALTER TABLE {table} ADD COLUMN {name} {ddl}")
