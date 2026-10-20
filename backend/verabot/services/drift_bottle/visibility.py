"""Visibility is the single gate for pages and model context.

Withdrawn/hidden text, content the viewer reported and authors the viewer
blocked are replaced by fixed placeholders on pages and never returned as body
text to the companion model.
"""
from __future__ import annotations

import json

from .contracts import BottleError
from ...db import drift_bottle_store as store

PLACEHOLDER_WITHDRAWN = "这段文字已被收回"
PLACEHOLDER_HIDDEN = "这段内容已被隐藏"
PLACEHOLDER_REPORTED = "你已举报这段内容"
PLACEHOLDER_BLOCKED = "你已屏蔽这位投稿者"


def _blocked_authors(c, user_id: int) -> set[int]:
    return store.blocked_author_ids(c, user_id)


def _report_hidden(c, user_id: int) -> set[int]:
    return store.report_hidden_contribution_ids(c, user_id)


def public_contribution(c, user_id: int, row: dict, *, blocked: set[int] | None = None,
                        reported: set[int] | None = None) -> dict:
    blocked = _blocked_authors(c, user_id) if blocked is None else blocked
    reported = _report_hidden(c, user_id) if reported is None else reported
    state = row["state"]
    author = row["author_user_id"]
    body = row["body"]
    display = "visible"
    if state == "withdrawn":
        body, display = PLACEHOLDER_WITHDRAWN, "withdrawn"
    elif state == "hidden":
        body, display = PLACEHOLDER_HIDDEN, "hidden"
    elif int(row["id"]) in reported:
        body, display = PLACEHOLDER_REPORTED, "reported"
    elif author is not None and int(author) in blocked:
        body, display = PLACEHOLDER_BLOCKED, "blocked"
    mine = author is not None and int(author) == int(user_id)
    return {
        "id": int(row["id"]),
        "bottle_id": int(row["bottle_id"]),
        "sequence": int(row["sequence"]),
        "kind": row["kind"],
        "body": body,
        "state": state,
        "display_state": display,
        "bot_name": row["bot_name"],
        "bot_avatar": row["bot_avatar"],
        "bot_color": row["bot_color"],
        "authorship": row["authorship"],
        "created_at": float(row["created_at"]),
        "is_mine": mine,
        "can_withdraw": mine and state == "visible",
        "can_report": (not mine) and state == "visible" and author is not None
        and int(row["id"]) not in reported and int(author) not in blocked,
    }


def public_contributions(c, user_id: int, rows: list[dict]) -> list[dict]:
    blocked = _blocked_authors(c, user_id)
    reported = _report_hidden(c, user_id)
    return [public_contribution(c, user_id, row, blocked=blocked, reported=reported) for row in rows]


def readable_bodies(c, user_id: int, bottle_id: int, read_limit: int) -> list[dict]:
    """Only text that may be shown to the model, in bottle order."""
    blocked = _blocked_authors(c, user_id)
    reported = _report_hidden(c, user_id)
    out = []
    for row in store.all_visible_contributions(c, bottle_id, read_limit):
        if row["state"] != "visible":
            continue
        if int(row["id"]) in reported:
            continue
        if row["author_user_id"] is not None and int(row["author_user_id"]) in blocked:
            continue
        out.append({"id": int(row["id"]), "sequence": int(row["sequence"]), "kind": row["kind"],
                    "body": row["body"], "bot_name": row["bot_name"],
                    "authorship": row["authorship"]})
    return out


def memory_dict(c, encounter_id: int) -> dict | None:
    row = store.memory_row(c, encounter_id)
    if row is None:
        return None
    try:
        source_turn_ids = json.loads(row["source_turn_ids"] or "[]")
    except (TypeError, ValueError):
        source_turn_ids = []
    return {
        "id": int(row["id"]),
        "encounter_id": int(row["encounter_id"]),
        "record_id": f"encounter:{int(row['encounter_id'])}",
        "title": row["title"],
        "summary": row["summary"],
        "owner_note": row["owner_note"],
        "edited": bool(row["owner_edited"]),
        "generated_by": row["generated_by"],
        "source_turn_ids": [int(value) for value in source_turn_ids],
        "version": int(row["version"]),
        "created_at": float(row["created_at"]),
        "updated_at": float(row["updated_at"]),
    }


def _turns(c, encounter_id: int) -> list[dict]:
    return [{
        "id": int(row["id"]),
        "role": row["role"],
        "kind": row["kind"],
        "content": row["content"],
        "created_at": float(row["created_at"]),
    } for row in store.turns_for(c, encounter_id)]


def _remaining(encounter: dict, now: float) -> int:
    return max(0, int(float(encounter["expires_at"]) - now))


def encounter_detail(c, user_id: int, encounter: dict, now: float, *,
                     cursor: int = 0, page: int = 20, all_pages: bool = False) -> dict:
    bottle = store.bottle_row(c, encounter["bottle_id"])
    if bottle is None:
        raise BottleError(404, "not_found", "这个瓶子不存在")
    if all_pages:
        rows = store.all_visible_contributions(c, bottle["id"], int(encounter["read_limit"]))
        next_cursor = None
    else:
        rows, next_cursor = store.contributions_page(c, bottle["id"], int(encounter["read_limit"]),
                                                     cursor, page)
    ended = encounter["ended_at"] is not None
    expired = (encounter["end_reason"] == "expired") or (not ended and now >= float(encounter["expires_at"]))
    return {
        "id": int(encounter["id"]),
        "bottle_id": int(encounter["bottle_id"]),
        "bot_id": encounter["bot_id"],
        "bot_name": encounter["bot_name"],
        "bot_avatar": encounter["bot_avatar"],
        "bot_color": encounter["bot_color"],
        "bot_deleted": encounter["bot_id"] is None,
        "started_at": float(encounter["started_at"]),
        "expires_at": float(encounter["expires_at"]),
        "ended_at": float(encounter["ended_at"]) if ended else None,
        "end_reason": encounter["end_reason"],
        "version": int(encounter["version"]),
        "bottle_version": int(bottle["version"]),
        "lease_token": encounter["lease_token"],
        "read_limit": int(encounter["read_limit"]),
        "quiet": bool(encounter["quiet"]),
        "remaining_seconds": _remaining(encounter, now),
        "is_expired": bool(expired),
        "can_publish": not ended and not expired,
        "contributions": public_contributions(c, user_id, rows),
        "next_cursor": str(next_cursor) if next_cursor is not None else None,
        "turns": _turns(c, int(encounter["id"])),
        "memory": memory_dict(c, int(encounter["id"])),
    }


def _preview(body: str, limit: int = 44) -> str:
    text = " ".join(body.split())
    return text if len(text) <= limit else text[:limit] + "…"


def record_summary(c, user_id: int, kind: str, row: dict) -> dict:
    if kind == "encounter":
        rows = store.all_visible_contributions(c, row["bottle_id"], int(row["read_limit"]))
        visible = [r for r in rows if r["state"] == "visible"]
        subtitle = _preview(visible[0]["body"]) if visible else "这封信里的文字已经被收回"
        title = f"和 {row['bot_name']} 一起读了一封信"
        created = float(row["started_at"])
        completed = float(row["ended_at"]) if row["ended_at"] is not None else None
        return {
            "id": f"encounter:{int(row['id'])}",
            "kind": "encounter",
            "title": title,
            "subtitle": subtitle,
            "bot_id": row["bot_id"],
            "bot_name": row["bot_name"],
            "bot_avatar": row["bot_avatar"],
            "bot_color": row["bot_color"],
            "created_at": created,
            "completed_at": completed,
            "has_memory": store.memory_row(c, int(row["id"])) is not None,
            "contribution_count": int(row["read_limit"]),
        }
    own = store.own_contributions(c, int(row["id"]), user_id)
    origin = own[0] if own else None
    subtitle = _preview(origin["body"]) if origin is not None and origin["state"] == "visible" else "原文已被收回"
    return {
        "id": f"release:{int(row['id'])}",
        "kind": "release",
        "title": "放漂了一封信",
        "subtitle": subtitle,
        "bot_id": row["origin_bot_id"],
        "bot_name": row["origin_bot_name"],
        "bot_avatar": row["origin_bot_avatar"],
        "bot_color": row["origin_bot_color"],
        "created_at": float(row["created_at"]),
        "completed_at": None,
        "has_memory": False,
        "contribution_count": int(row["public_count"]),
    }


def release_detail(c, user_id: int, bottle: dict) -> dict:
    own = store.own_contributions(c, int(bottle["id"]), user_id)
    return {
        "bottle_id": int(bottle["id"]),
        "state": bottle["state"],
        "public_count": int(bottle["public_count"]),
        "created_at": float(bottle["created_at"]),
        "bot_id": bottle["origin_bot_id"],
        "bot_name": bottle["origin_bot_name"],
        "bot_avatar": bottle["origin_bot_avatar"],
        "bot_color": bottle["origin_bot_color"],
        "contributions": public_contributions(c, user_id, own),
    }


def record_detail(c, user_id: int, record_id: str, now: float) -> dict:
    kind, raw = store.parse_record_id(record_id)
    if kind == "encounter":
        encounter = store.encounter_row(c, user_id, raw)
        detail = encounter_detail(c, user_id, encounter, now, all_pages=True)
        # The record also keeps the owner's own public contributions published
        # after this encounter's read limit (normally the message left on release).
        own = [row for row in store.own_contributions(c, encounter["bottle_id"], user_id)
               if int(row["sequence"]) > int(encounter["read_limit"])]
        if own:
            seen = {row["id"] for row in detail["contributions"]}
            detail["contributions"].extend(item for item in public_contributions(c, user_id, own)
                                           if item["id"] not in seen)
            detail["contributions"].sort(key=lambda item: item["sequence"])
        summary = record_summary(c, user_id, "encounter", encounter)
        return {
            "id": record_id,
            "kind": "encounter",
            "title": summary["title"],
            "subtitle": summary["subtitle"],
            "created_at": summary["created_at"],
            "completed_at": summary["completed_at"],
            "encounter": detail,
            "release": None,
            "contributions": detail["contributions"],
            "turns": detail["turns"],
            "memory": detail["memory"],
        }
    bottle = store.release_bottle(c, user_id, raw)
    release = release_detail(c, user_id, bottle)
    summary = record_summary(c, user_id, "release", bottle)
    return {
        "id": record_id,
        "kind": "release",
        "title": summary["title"],
        "subtitle": summary["subtitle"],
        "created_at": summary["created_at"],
        "completed_at": None,
        "encounter": None,
        "release": release,
        "contributions": release["contributions"],
        "turns": [],
        "memory": None,
    }
