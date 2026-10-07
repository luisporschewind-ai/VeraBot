"""Tenant-scoped storage for bounded memory suggestions."""
from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone

from .database import now_iso, row, rows, tx

MAX_PAYLOAD_BYTES = 4096
VALID_KINDS = {"routine_reminder", "delegation"}
VALID_DECISIONS = {"accepted", "dismissed"}


def _utc(value: str) -> datetime:
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return parsed.replace(tzinfo=timezone.utc) if parsed.tzinfo is None else parsed.astimezone(timezone.utc)


def _payload_json(payload: dict) -> str:
    if not isinstance(payload, dict):
        raise ValueError("payload_must_be_object")
    encoded = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
    if len(encoded.encode("utf-8")) > MAX_PAYLOAD_BYTES:
        raise ValueError("payload_too_large")
    return encoded


def create_or_get_active(*, user_id: int, bot_id: int, kind: str, dedupe_key: str,
                         payload: dict, expires_at: str) -> dict:
    if kind not in VALID_KINDS or not dedupe_key or len(dedupe_key) > 160:
        raise ValueError("invalid_suggestion")
    body = _payload_json(payload)
    now = now_iso()
    with tx() as c:
        c.execute("BEGIN IMMEDIATE")
        active = row(c.execute(
            "SELECT * FROM suggestions WHERE user_id=? AND bot_id=? AND kind=? AND dedupe_key=? "
            "AND status='pending' AND expires_at>? ORDER BY id DESC LIMIT 1",
            (user_id, bot_id, kind, dedupe_key, now),
        ).fetchone())
        if active:
            return active
        cooldown_start = (datetime.now(timezone.utc) - timedelta(days=30)).isoformat()
        dismissed = row(c.execute(
            "SELECT * FROM suggestions WHERE user_id=? AND bot_id=? AND kind=? AND dedupe_key=? "
            "AND status='dismissed' AND decided_at>? ORDER BY id DESC LIMIT 1",
            (user_id, bot_id, kind, dedupe_key, cooldown_start),
        ).fetchone())
        if dismissed:
            return dismissed
        accepted = row(c.execute(
            "SELECT * FROM suggestions WHERE user_id=? AND bot_id=? AND kind=? AND dedupe_key=? "
            "AND status='accepted' ORDER BY id DESC LIMIT 1",
            (user_id, bot_id, kind, dedupe_key),
        ).fetchone())
        if accepted:
            return accepted
        c.execute(
            "UPDATE suggestions SET status='expired' WHERE user_id=? AND bot_id=? AND kind=? "
            "AND dedupe_key=? AND status='pending' AND expires_at<=?",
            (user_id, bot_id, kind, dedupe_key, now),
        )
        cur = c.execute(
            "INSERT INTO suggestions(user_id,bot_id,kind,dedupe_key,payload,status,created_at,expires_at) "
            "VALUES (?,?,?,?,?,'pending',?,?)",
            (user_id, bot_id, kind, dedupe_key, body, now, expires_at),
        )
        return row(c.execute("SELECT * FROM suggestions WHERE id=? AND user_id=?",
                             (cur.lastrowid, user_id)).fetchone())


def list_pending(user_id: int, bot_id: int) -> list[dict]:
    now = now_iso()
    with tx() as c:
        c.execute("UPDATE suggestions SET status='expired' WHERE user_id=? AND bot_id=? "
                  "AND status='pending' AND expires_at<=?", (user_id, bot_id, now))
        return rows(c.execute(
            "SELECT * FROM suggestions WHERE user_id=? AND bot_id=? AND status='pending' "
            "AND expires_at>? ORDER BY created_at,id", (user_id, bot_id, now),
        ).fetchall())


def decide(user_id: int, suggestion_id: int, decision: str) -> dict | None:
    if decision not in VALID_DECISIONS:
        raise ValueError("invalid_decision")
    with tx() as c:
        c.execute("BEGIN IMMEDIATE")
        current = row(c.execute("SELECT * FROM suggestions WHERE id=? AND user_id=?",
                                (suggestion_id, user_id)).fetchone())
        if current is None:
            return None
        if current["status"] == "pending" and _utc(current["expires_at"]) > datetime.now(timezone.utc):
            c.execute("UPDATE suggestions SET status=?, decided_at=? WHERE id=? AND user_id=? AND status='pending'",
                      (decision, now_iso(), suggestion_id, user_id))
            current = row(c.execute("SELECT * FROM suggestions WHERE id=? AND user_id=?",
                                    (suggestion_id, user_id)).fetchone())
        elif current["status"] == "pending":
            c.execute("UPDATE suggestions SET status='expired' WHERE id=? AND user_id=? AND status='pending'",
                      (suggestion_id, user_id))
            current["status"] = "expired"
        return current
