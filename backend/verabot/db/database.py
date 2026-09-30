"""SQLite 连接与事务（Connection & transaction）。所有查询都必须带 user_id 条件以保证租户隔离。"""
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone

from ..core.config import DB_PATH


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def connect() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


@contextmanager
def tx():
    conn = connect()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def row(r):
    return dict(r) if r is not None else None


def rows(rs):
    return [dict(r) for r in rs]
