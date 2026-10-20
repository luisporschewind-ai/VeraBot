"""Transactional Drift Bottle storage. Caller owns BEGIN IMMEDIATE/commit.

No model calls happen here and no transaction is held while waiting for one.
Every private read is scoped by user_id; public contribution DTOs are built by
the visibility layer so author identities never leak.
"""
from __future__ import annotations

import json
from typing import Any
from uuid import uuid4

from ..services.drift_bottle.contracts import (
    HOLD_SECONDS, MAX_CONTRIBUTIONS, BottleError,
)


def _json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _loads(value: str | None, fallback):
    if not value:
        return fallback
    try:
        return json.loads(value)
    except (TypeError, ValueError):
        return fallback


def bot_for_user(c, user_id: int, bot_id: int) -> dict:
    row = c.execute("SELECT * FROM bots WHERE id=? AND user_id=?", (bot_id, user_id)).fetchone()
    if row is None:
        raise BottleError(404, "bot_not_found", "Bot 不存在")
    return dict(row)


def encounter_bot_deleted(row: dict) -> bool:
    return row.get("bot_id") is None


# ---------------------------------------------------------------------------
# Operations and idempotency
# ---------------------------------------------------------------------------


def operation_row(c, user_id: int, request_id: str):
    row = c.execute("SELECT * FROM drift_bottle_operations WHERE user_id=? AND request_id=?",
                    (user_id, request_id)).fetchone()
    return dict(row) if row else None


def replay(c, user_id: int, request_id: str, payload_hash: str, now: float):
    """Return the committed result, raise on conflict/fresh pending, or None to execute."""
    row = operation_row(c, user_id, request_id)
    if row is None:
        return None
    if row["payload_hash"] != payload_hash:
        raise BottleError(409, "request_conflict", "同一个请求 ID 不能用于不同内容")
    if row["status"] == "committed":
        return _loads(row["result_json"], {})
    if row["status"] == "pending" and now - float(row["updated_at"]) < 120:
        raise BottleError(409, "operation_pending", "这次操作还在处理中，请稍后查询结果")
    # Failed or stale pending: retry with the same request id.
    return None


def begin_operation(c, user_id: int, request_id: str, kind: str, payload_hash: str, now: float):
    c.execute("""INSERT INTO drift_bottle_operations
      (user_id,request_id,kind,payload_hash,status,result_json,error_json,created_at,updated_at)
      VALUES(?,?,?,?,'pending',NULL,NULL,?,?)
      ON CONFLICT(user_id,request_id) DO UPDATE SET
        kind=excluded.kind,payload_hash=excluded.payload_hash,status='pending',
        result_json=NULL,error_json=NULL,updated_at=excluded.updated_at""",
              (user_id, request_id, kind, payload_hash, now, now))


def complete_operation(c, user_id: int, request_id: str, kind: str, payload_hash: str,
                       result: dict, now: float):
    c.execute("""INSERT INTO drift_bottle_operations
      (user_id,request_id,kind,payload_hash,status,result_json,error_json,created_at,updated_at)
      VALUES(?,?,?,?,'committed',?,NULL,?,?)
      ON CONFLICT(user_id,request_id) DO UPDATE SET
        kind=excluded.kind,payload_hash=excluded.payload_hash,status='committed',
        result_json=excluded.result_json,error_json=NULL,updated_at=excluded.updated_at""",
              (user_id, request_id, kind, payload_hash, _json(result), now, now))


def fail_operation(c, user_id: int, request_id: str, code: str, message: str, now: float):
    c.execute("""UPDATE drift_bottle_operations SET status='failed',error_json=?,updated_at=?
                 WHERE user_id=? AND request_id=?""",
              (_json({"code": code, "message": message}), now, user_id, request_id))


def claim_generation(c, encounter_id: int, request_id: str, owner: str, now: float):
    row = c.execute("SELECT * FROM drift_bottle_generation_locks WHERE encounter_id=?",
                    (encounter_id,)).fetchone()
    if row is not None:
        row = dict(row)
        if row["request_id"] != request_id and now - float(row["updated_at"]) < 120:
            raise BottleError(409, "generation_busy", "Bot 正在回应上一条消息，请稍等")
    c.execute("""INSERT INTO drift_bottle_generation_locks(encounter_id,request_id,owner,updated_at)
                 VALUES(?,?,?,?)
                 ON CONFLICT(encounter_id) DO UPDATE SET request_id=excluded.request_id,
                   owner=excluded.owner,updated_at=excluded.updated_at""",
              (encounter_id, request_id, owner, now))


def release_generation(c, encounter_id: int, request_id: str):
    c.execute("DELETE FROM drift_bottle_generation_locks WHERE encounter_id=? AND request_id=?",
              (encounter_id, request_id))


def operation_info(row: dict) -> dict:
    error = _loads(row.get("error_json"), {}) or {}
    return {
        "request_id": row["request_id"],
        "status": row["status"],
        "kind": row["kind"],
        "error_code": error.get("code"),
        "error_message": error.get("message"),
        "retryable": row["status"] == "failed",
    }


# ---------------------------------------------------------------------------
# Bottles, contributions and encounters
# ---------------------------------------------------------------------------


def bottle_row(c, bottle_id: int, for_update: bool = False):
    sql = "SELECT * FROM drift_bottles WHERE id=?"
    if for_update:
        sql += " "
    row = c.execute(sql, (bottle_id,)).fetchone()
    return dict(row) if row else None


def contribution_row(c, contribution_id: int):
    row = c.execute("SELECT * FROM drift_bottle_contributions WHERE id=?", (contribution_id,)).fetchone()
    return dict(row) if row else None


def active_encounter_row(c, user_id: int):
    row = c.execute("SELECT * FROM drift_bottle_encounters WHERE user_id=? AND ended_at IS NULL",
                    (user_id,)).fetchone()
    return dict(row) if row else None


def encounter_row(c, user_id: int, encounter_id: int, include_hidden: bool = False):
    row = c.execute("SELECT * FROM drift_bottle_encounters WHERE id=? AND user_id=?",
                    (encounter_id, user_id)).fetchone()
    if row is None:
        raise BottleError(404, "not_found", "这次相遇不存在")
    data = dict(row)
    if not include_hidden and record_hidden(c, user_id, "encounter", encounter_id):
        raise BottleError(404, "not_found", "这次相遇不存在")
    return data


def record_hidden(c, user_id: int, record_type: str, record_id: int) -> bool:
    return c.execute("""SELECT 1 FROM drift_bottle_record_hides
                        WHERE user_id=? AND record_type=? AND record_id=?""",
                     (user_id, record_type, record_id)).fetchone() is not None


def hide_record(c, user_id: int, record_type: str, record_id: int, now: float):
    c.execute("""INSERT OR IGNORE INTO drift_bottle_record_hides
                 (user_id,record_type,record_id,hidden_at) VALUES(?,?,?,?)""",
              (user_id, record_type, record_id, now))


def expire_active(c, user_id: int, now: float) -> list[dict]:
    rows = c.execute("""SELECT * FROM drift_bottle_encounters
                        WHERE user_id=? AND ended_at IS NULL AND expires_at<=?""",
                     (user_id, now)).fetchall()
    expired = []
    for row in rows:
        data = dict(row)
        c.execute("""UPDATE drift_bottle_encounters
                     SET ended_at=?,end_reason='expired',version=version+1,last_activity_at=?
                     WHERE id=? AND ended_at IS NULL""",
                  (now, now, data["id"]))
        data["ended_at"] = now
        data["end_reason"] = "expired"
        expired.append(data)
        ensure_fact_memory(c, data["user_id"], data["id"], data, now)
    return expired


def candidate_bottle(c, user_id: int):
    row = c.execute("""
      SELECT b.* FROM drift_bottles b
      WHERE b.state='active' AND b.public_count < ?
        AND EXISTS(SELECT 1 FROM drift_bottle_contributions v
                    WHERE v.bottle_id=b.id AND v.state='visible')
        AND NOT EXISTS(SELECT 1 FROM drift_bottle_encounters e
                        WHERE e.bottle_id=b.id AND e.ended_at IS NULL)
        AND NOT EXISTS(SELECT 1 FROM drift_bottle_contributions own
                        WHERE own.bottle_id=b.id AND own.author_user_id=?)
        AND NOT EXISTS(SELECT 1 FROM drift_bottle_reads r
                        WHERE r.bottle_id=b.id AND r.user_id=?)
        AND NOT EXISTS(SELECT 1 FROM drift_bottle_contributions blocked
                        JOIN drift_bottle_blocks bl
                          ON bl.blocked_user_id=blocked.author_user_id AND bl.user_id=?
                        WHERE blocked.bottle_id=b.id AND blocked.state='visible')
      ORDER BY RANDOM() LIMIT 1""", (MAX_CONTRIBUTIONS, user_id, user_id, user_id)).fetchone()
    return dict(row) if row else None


def create_bottle_tx(c, user_id: int, bot: dict, body: str, authorship: str, now: float):
    cursor = c.execute("""INSERT INTO drift_bottles
      (origin_user_id,origin_bot_id,origin_bot_name,origin_bot_avatar,origin_bot_color,state,public_count,version,created_at,last_activity_at)
      VALUES(?,?,?,?,?,'active',1,1,?,?)""",
                       (user_id, bot["id"], bot["name"], bot.get("avatar") or "🤖",
                        bot.get("color") or "#0F766E", now, now))
    bottle_id = int(cursor.lastrowid)
    contribution = c.execute("""INSERT INTO drift_bottle_contributions
      (bottle_id,author_user_id,sequence,kind,body,state,authorship,bot_id,bot_name,bot_avatar,bot_color,created_at)
      VALUES(?,?,1,'origin',?,'visible',?,?,?,?,?,?)""",
                             (bottle_id, user_id, body, authorship, bot["id"], bot["name"],
                              bot.get("avatar") or "🤖", bot.get("color") or "#0F766E", now))
    return bottle_id, int(contribution.lastrowid)


def draw_tx(c, user_id: int, bot: dict, now: float):
    active = active_encounter_row(c, user_id)
    if active is not None:
        return active["id"], True
    bottle = candidate_bottle(c, user_id)
    if bottle is None:
        return None, False
    token = str(uuid4())
    cursor = c.execute("""INSERT INTO drift_bottle_encounters
      (user_id,bot_id,bottle_id,bot_name,bot_avatar,bot_color,lease_token,read_limit,started_at,expires_at,version,quiet,last_activity_at)
      VALUES(?,?,?,?,?,?,?,?,?,?,1,0,?)""",
                       (user_id, bot["id"], bottle["id"], bot["name"], bot.get("avatar") or "🤖",
                        bot.get("color") or "#0F766E", token, bottle["public_count"],
                        now, now + HOLD_SECONDS, now))
    encounter_id = int(cursor.lastrowid)
    c.execute("""INSERT OR IGNORE INTO drift_bottle_reads(user_id,bottle_id,encounter_id,read_at)
                 VALUES(?,?,?,?)""", (user_id, bottle["id"], encounter_id, now))
    return encounter_id, False


def contributions_page(c, bottle_id: int, read_limit: int, after: int, limit: int):
    rows = c.execute("""SELECT * FROM drift_bottle_contributions
                        WHERE bottle_id=? AND sequence<=? AND sequence>?
                        ORDER BY sequence LIMIT ?""",
                     (bottle_id, read_limit, after, limit + 1)).fetchall()
    data = [dict(row) for row in rows]
    more = len(data) > limit
    data = data[:limit]
    return data, (data[-1]["sequence"] if more and data else None)


def all_visible_contributions(c, bottle_id: int, read_limit: int):
    rows = c.execute("""SELECT * FROM drift_bottle_contributions
                        WHERE bottle_id=? AND sequence<=? ORDER BY sequence""",
                     (bottle_id, read_limit)).fetchall()
    return [dict(row) for row in rows]


def turns_for(c, encounter_id: int, *, include_drafts: bool = False):
    sql = "SELECT * FROM drift_bottle_turns WHERE encounter_id=? AND visible=1"
    if not include_drafts:
        sql += " AND kind!='draft'"
    sql += " ORDER BY id"
    return [dict(row) for row in c.execute(sql, (encounter_id,)).fetchall()]


def turn_by_event(c, encounter_id: int, event_key: str):
    row = c.execute("SELECT * FROM drift_bottle_turns WHERE encounter_id=? AND event_key=?",
                    (encounter_id, event_key)).fetchone()
    return dict(row) if row else None


def append_turn_tx(c, encounter_id: int, *, role: str, kind: str, content: str,
                   request_id: str | None, event_key: str | None, now: float):
    if event_key is not None:
        existing = turn_by_event(c, encounter_id, event_key)
        if existing is not None:
            return existing
    cursor = c.execute("""INSERT INTO drift_bottle_turns
      (encounter_id,role,kind,content,request_id,event_key,created_at,visible)
      VALUES(?,?,?,?,?,?,?,1)""",
                       (encounter_id, role, kind, content, request_id, event_key, now))
    return {"id": int(cursor.lastrowid), "encounter_id": encounter_id, "role": role,
            "kind": kind, "content": content, "request_id": request_id,
            "event_key": event_key, "created_at": now, "visible": 1}


def set_quiet(c, encounter_id: int, now: float):
    c.execute("""UPDATE drift_bottle_encounters SET quiet=1,version=version+1,last_activity_at=?
                 WHERE id=? AND quiet=0 AND ended_at IS NULL""", (now, encounter_id))


def release_tx(c, user_id: int, encounter: dict, contribution: dict | None,
               expected_version: int, now: float):
    if encounter["ended_at"] is not None:
        if encounter["end_reason"] == "expired":
            raise BottleError(409, "encounter_expired", "这次相遇已到期，可以继续和 Bot 聊，但不能追加留言")
        raise BottleError(409, "encounter_ended", "这次相遇已经结束")
    if now >= float(encounter["expires_at"]):
        c.execute("""UPDATE drift_bottle_encounters SET ended_at=?,end_reason='expired',
                     version=version+1,last_activity_at=? WHERE id=?""", (now, now, encounter["id"]))
        ensure_fact_memory(c, user_id, encounter["id"], encounter, now)
        raise BottleError(409, "encounter_expired", "这次相遇已到期，可以继续和 Bot 聊，但不能追加留言")
    bottle = bottle_row(c, encounter["bottle_id"])
    if bottle is None:
        raise BottleError(404, "not_found", "这个瓶子不存在")
    if int(bottle["version"]) != int(expected_version):
        raise BottleError(409, "version_conflict", "瓶子内容已变化，请重新载入后再试")
    new_contribution_id = None
    if contribution is not None:
        if int(bottle["public_count"]) >= MAX_CONTRIBUTIONS:
            raise BottleError(409, "bottle_full", "这个瓶子已经收满 50 条投稿")
        sequence = int(bottle["public_count"]) + 1
        cursor = c.execute("""INSERT INTO drift_bottle_contributions
          (bottle_id,author_user_id,sequence,kind,body,state,authorship,bot_id,bot_name,bot_avatar,bot_color,created_at)
          VALUES(?,?,?,'message',?,'visible',?,?,?,?,?,?)""",
                           (bottle["id"], user_id, sequence, contribution["body"],
                            contribution["authorship"], encounter["bot_id"], encounter["bot_name"],
                            encounter["bot_avatar"], encounter["bot_color"], now))
        new_contribution_id = int(cursor.lastrowid)
        count = sequence
        state = "archived" if count >= MAX_CONTRIBUTIONS else ("active" if bottle["state"] == "empty" else bottle["state"])
        c.execute("""UPDATE drift_bottles SET public_count=?,state=?,version=version+1,
                     last_activity_at=?,archived_at=? WHERE id=?""",
                  (count, state, now, now if state == "archived" else bottle.get("archived_at"), bottle["id"]))
    reason = "released" if contribution is not None else "returned"
    c.execute("""UPDATE drift_bottle_encounters SET ended_at=?,end_reason=?,version=version+1,
                 last_activity_at=? WHERE id=? AND ended_at IS NULL""",
              (now, reason, now, encounter["id"]))
    ensure_fact_memory(c, user_id, encounter["id"], encounter, now, own_contribution=new_contribution_id)
    return new_contribution_id


# ---------------------------------------------------------------------------
# Memories
# ---------------------------------------------------------------------------


def memory_row(c, encounter_id: int):
    row = c.execute("SELECT * FROM drift_bottle_memories WHERE encounter_id=?", (encounter_id,)).fetchone()
    return dict(row) if row else None


def ensure_fact_memory(c, user_id: int, encounter_id: int, encounter: dict, now: float,
                       own_contribution: int | None = None):
    existing = memory_row(c, encounter_id)
    if existing is not None:
        return existing
    read_limit = int(encounter.get("read_limit") or 0)
    contributions = all_visible_contributions(c, encounter["bottle_id"], read_limit)
    visible = [row for row in contributions if row["state"] == "visible"]
    turns = turns_for(c, encounter_id)
    chat_turns = [row for row in turns if row["kind"] == "chat"]
    rounds = sum(1 for row in chat_turns if row["role"] == "user")
    parts = ["我们一起读了一封来信"]
    if rounds:
        parts.append(f"和 Bot 聊了 {rounds} 轮")
    if own_contribution is not None or any(row["author_user_id"] == user_id and row["kind"] == "message" for row in visible):
        parts.append("也留下了一句")
    summary = "，".join(parts) + "。"
    source_ids = [int(row["id"]) for row in visible]
    if own_contribution is not None:
        source_ids.append(int(own_contribution))
    source_turn_ids = [int(row["id"]) for row in turns]
    c.execute("""INSERT OR IGNORE INTO drift_bottle_memories
      (encounter_id,user_id,title,summary,owner_note,source_turn_ids,source_contribution_ids,
       generated_by,owner_edited,version,created_at,updated_at)
      VALUES(?,?,?,?,'',?,?,'fact',0,1,?,?)""",
              (encounter_id, user_id, "我们一起读了一封来信", summary,
               _json(source_turn_ids), _json(source_ids), now, now))
    return memory_row(c, encounter_id)


def save_generated_memory(c, user_id: int, encounter_id: int, title: str, summary: str,
                          source_turn_ids: list[int], source_ids: list[int], now: float):
    existing = memory_row(c, encounter_id)
    if existing is None:
        cursor = c.execute("""INSERT INTO drift_bottle_memories
          (encounter_id,user_id,title,summary,owner_note,source_turn_ids,source_contribution_ids,
           generated_by,owner_edited,version,created_at,updated_at)
          VALUES(?,?,?,?,'',?,?,'bot',0,1,?,?)""",
                           (encounter_id, user_id, title, summary, _json(source_turn_ids),
                            _json(source_ids), now, now))
        return memory_row(c, encounter_id) or {"id": int(cursor.lastrowid)}
    if existing["owner_edited"]:
        return existing
    c.execute("""UPDATE drift_bottle_memories SET title=?,summary=?,source_turn_ids=?,
                 source_contribution_ids=?,generated_by='bot',version=version+1,updated_at=?
                 WHERE id=? AND owner_edited=0""",
              (title, summary, _json(source_turn_ids), _json(source_ids), now, existing["id"]))
    return memory_row(c, encounter_id)


def patch_memory(c, user_id: int, encounter_id: int, patch: dict, now: float):
    memory = memory_row(c, encounter_id)
    if memory is None:
        raise BottleError(404, "not_found", "回忆卡不存在")
    expected = patch.get("expected_version")
    if expected is not None and int(expected) != int(memory["version"]):
        raise BottleError(409, "version_conflict", "回忆卡已更新，请重新载入")
    fields, values = [], []
    for key in ("title", "summary", "owner_note"):
        value = patch.get(key)
        if value is not None:
            fields.append(f"{key}=?")
            values.append(value)
    if not fields:
        return memory
    fields.extend(["owner_edited=1", "version=version+1", "updated_at=?"])
    values.extend([now, memory["id"]])
    c.execute(f"UPDATE drift_bottle_memories SET {','.join(fields)} WHERE id=?", values)
    return memory_row(c, encounter_id)


def delete_memory(c, user_id: int, encounter_id: int):
    memory = memory_row(c, encounter_id)
    if memory is None:
        raise BottleError(404, "not_found", "回忆卡不存在")
    c.execute("DELETE FROM drift_bottle_memories WHERE encounter_id=?", (encounter_id,))
    return memory


# ---------------------------------------------------------------------------
# Moderation
# ---------------------------------------------------------------------------


def withdraw_tx(c, user_id: int, contribution: dict, now: float):
    if contribution["author_user_id"] != user_id:
        raise BottleError(404, "not_found", "这条投稿不存在")
    bottle = bottle_row(c, contribution["bottle_id"])
    if bottle is None:
        raise BottleError(404, "not_found", "这个瓶子不存在")
    if contribution["state"] == "withdrawn":
        return contribution
    c.execute("""UPDATE drift_bottle_contributions SET state='withdrawn',body='',withdrawn_at=?
                 WHERE id=?""", (now, contribution["id"]))
    has_visible = c.execute("""SELECT 1 FROM drift_bottle_contributions
                               WHERE bottle_id=? AND state='visible' LIMIT 1""",
                            (bottle["id"],)).fetchone() is not None
    state = bottle["state"]
    if not has_visible and state == "active":
        state = "empty"
    c.execute("UPDATE drift_bottles SET state=?,version=version+1,last_activity_at=? WHERE id=?",
              (state, now, bottle["id"]))
    return contribution_row(c, contribution["id"])


def report_tx(c, user_id: int, contribution: dict, reason: str, now: float):
    if contribution["author_user_id"] == user_id:
        raise BottleError(400, "own_contribution", "不能举报自己的投稿")
    existing = c.execute("""SELECT * FROM drift_bottle_reports
                            WHERE contribution_id=? AND reporter_user_id=? AND state='pending'
                            ORDER BY id DESC LIMIT 1""",
                         (contribution["id"], user_id)).fetchone()
    if existing is not None:
        report = dict(existing)
    else:
        cursor = c.execute("""INSERT INTO drift_bottle_reports
          (contribution_id,reporter_user_id,reason,state,created_at)
          VALUES(?,?,?,'pending',?)""", (contribution["id"], user_id, reason, now))
        report = {"id": int(cursor.lastrowid), "contribution_id": contribution["id"],
                  "reporter_user_id": user_id, "reason": reason, "state": "pending", "created_at": now}
    c.execute("""INSERT OR IGNORE INTO drift_bottle_report_hides
                 (user_id,contribution_id,report_id,created_at) VALUES(?,?,?,?)""",
              (user_id, contribution["id"], report["id"], now))
    return report


def block_tx(c, user_id: int, contribution: dict, now: float):
    author = contribution["author_user_id"]
    if author is None:
        raise BottleError(409, "author_unavailable", "这位投稿者已不存在")
    if author == user_id:
        raise BottleError(400, "own_contribution", "不能屏蔽自己")
    c.execute("""INSERT OR IGNORE INTO drift_bottle_blocks(user_id,blocked_user_id,created_at)
                 VALUES(?,?,?)""", (user_id, author, now))
    return author


def pending_reports(c):
    rows = c.execute("""SELECT r.*,c.body,c.state AS contribution_state,c.bot_name
                        FROM drift_bottle_reports r JOIN drift_bottle_contributions c ON c.id=r.contribution_id
                        WHERE r.state='pending' ORDER BY r.id""").fetchall()
    return [dict(row) for row in rows]


def ensure_admin(admin_id: int, admins: set[int] | None = None):
    if admins is None:
        from ...core.config import DRIFT_BOTTLE_ADMINS
        admins = DRIFT_BOTTLE_ADMINS
    if int(admin_id) not in {int(x) for x in admins}:
        raise BottleError(403, "admin_required", "需要漂流瓶管理员权限")


def moderate_tx(c, admin_id: int, report_id: int, action: str, reason: str, now: float,
                admins: set[int] | None = None):
    ensure_admin(admin_id, admins)
    report = c.execute("SELECT * FROM drift_bottle_reports WHERE id=?", (report_id,)).fetchone()
    if report is None:
        raise BottleError(404, "not_found", "举报不存在")
    report = dict(report)
    contribution = contribution_row(c, report["contribution_id"])
    if contribution is None:
        raise BottleError(404, "not_found", "投稿不存在")
    state = {"keep": "kept", "hide": "hidden", "restore": "restored"}[action]
    c.execute("""UPDATE drift_bottle_reports SET state=?,resolved_at=?,resolved_by=?
                 WHERE id=?""", (state, now, admin_id, report_id))
    if action == "hide":
        if contribution["state"] == "visible":
            c.execute("UPDATE drift_bottle_contributions SET state='hidden',hidden_at=? WHERE id=?",
                      (now, contribution["id"]))
        _refresh_bottle_state(c, contribution["bottle_id"], now)
    elif action == "restore":
        if contribution["state"] == "hidden":
            c.execute("UPDATE drift_bottle_contributions SET state='visible',hidden_at=NULL WHERE id=?",
                      (contribution["id"],))
        c.execute("DELETE FROM drift_bottle_report_hides WHERE report_id=?", (report_id,))
        _refresh_bottle_state(c, contribution["bottle_id"], now)
    c.execute("""INSERT INTO drift_bottle_moderation_actions
                 (report_id,admin_user_id,action,reason,created_at) VALUES(?,?,?,?,?)""",
              (report_id, admin_id, action, reason or "", now))
    return {"report_id": report_id, "action": action, "state": state,
            "contribution_state": contribution_row(c, contribution["id"])["state"]}


def _refresh_bottle_state(c, bottle_id: int, now: float):
    bottle = bottle_row(c, bottle_id)
    if bottle is None:
        return
    visible = c.execute("""SELECT 1 FROM drift_bottle_contributions
                           WHERE bottle_id=? AND state='visible' LIMIT 1""",
                        (bottle_id,)).fetchone() is not None
    if not visible and bottle["state"] == "active":
        c.execute("UPDATE drift_bottles SET state='empty',version=version+1,last_activity_at=? WHERE id=?",
                  (now, bottle_id))
    elif visible and bottle["state"] == "empty" and int(bottle["public_count"]) < MAX_CONTRIBUTIONS:
        c.execute("UPDATE drift_bottles SET state='active',version=version+1,last_activity_at=? WHERE id=?",
                  (now, bottle_id))


# ---------------------------------------------------------------------------
# Records and cleanup
# ---------------------------------------------------------------------------


def parse_record_id(record_id: str):
    if ":" not in record_id:
        raise BottleError(404, "not_found", "这条记录不存在")
    kind, raw = record_id.split(":", 1)
    if kind not in ("encounter", "release") or not raw.isdigit() or int(raw) <= 0:
        raise BottleError(404, "not_found", "这条记录不存在")
    return kind, int(raw)


def record_rows(c, user_id: int, bot_id: int | None):
    encounters = c.execute("""
      SELECT e.*,b.public_count AS bottle_public_count,b.state AS bottle_state,
             b.origin_bot_name,b.origin_bot_avatar
        FROM drift_bottle_encounters e JOIN drift_bottles b ON b.id=e.bottle_id
       WHERE e.user_id=? AND NOT EXISTS(
         SELECT 1 FROM drift_bottle_record_hides h
          WHERE h.user_id=? AND h.record_type='encounter' AND h.record_id=e.id)
         AND (? IS NULL OR e.bot_id=?)
       ORDER BY e.started_at DESC,e.id DESC""",
                              (user_id, user_id, bot_id, bot_id)).fetchall()
    releases = c.execute("""
      SELECT b.* FROM drift_bottles b
       WHERE b.origin_user_id=?
         AND EXISTS(SELECT 1 FROM drift_bottle_contributions c
                     WHERE c.bottle_id=b.id AND c.author_user_id=? AND c.kind='origin')
         AND NOT EXISTS(SELECT 1 FROM drift_bottle_record_hides h
                         WHERE h.user_id=? AND h.record_type='release' AND h.record_id=b.id)
         AND (? IS NULL OR b.origin_bot_id=?)
       ORDER BY b.created_at DESC,b.id DESC""",
                           (user_id, user_id, user_id, bot_id, bot_id)).fetchall()
    return [dict(row) for row in encounters], [dict(row) for row in releases]


def release_bottle(c, user_id: int, bottle_id: int):
    row = c.execute("""SELECT b.* FROM drift_bottles b
                       WHERE b.id=? AND b.origin_user_id=?
                         AND EXISTS(SELECT 1 FROM drift_bottle_contributions c
                                     WHERE c.bottle_id=b.id AND c.author_user_id=? AND c.kind='origin')""",
                    (bottle_id, user_id, user_id)).fetchone()
    if row is None or record_hidden(c, user_id, "release", bottle_id):
        raise BottleError(404, "not_found", "这条记录不存在")
    return dict(row)


def own_contributions(c, bottle_id: int, user_id: int):
    return [dict(row) for row in c.execute("""SELECT * FROM drift_bottle_contributions
                                               WHERE bottle_id=? AND author_user_id=?
                                               ORDER BY sequence""", (bottle_id, user_id)).fetchall()]


def delete_record_tx(c, user_id: int, record_id: str, now: float):
    kind, raw = parse_record_id(record_id)
    if kind == "encounter":
        encounter = encounter_row(c, user_id, raw)
        if encounter["ended_at"] is None:
            raise BottleError(409, "encounter_active", "请先把瓶子放回，再删除这次记录")
        c.execute("DELETE FROM drift_bottle_encounters WHERE id=? AND user_id=?", (raw, user_id))
        hide_record(c, user_id, "encounter", raw, now)
        return {"record_id": record_id, "deleted": True}
    bottle = release_bottle(c, user_id, raw)
    hide_record(c, user_id, "release", raw, now)
    return {"record_id": record_id, "deleted": True}


def cleanup_user(c, user_id: int, now: float):
    """Withdraw public text and remove private rows before/without a row delete."""
    c.execute("""UPDATE drift_bottle_contributions SET state='withdrawn',body='',withdrawn_at=?
                 WHERE author_user_id=? AND state!='withdrawn'""", (now, user_id))
    bottles = c.execute("SELECT id FROM drift_bottles WHERE origin_user_id=?", (user_id,)).fetchall()
    for bottle in bottles:
        _refresh_bottle_state(c, bottle["id"], now)
    c.execute("DELETE FROM drift_bottle_encounters WHERE user_id=?", (user_id,))
    c.execute("DELETE FROM drift_bottle_operations WHERE user_id=?", (user_id,))
    c.execute("DELETE FROM drift_bottle_blocks WHERE user_id=? OR blocked_user_id=?", (user_id, user_id))
    c.execute("DELETE FROM drift_bottle_reports WHERE reporter_user_id=?", (user_id,))
    c.execute("DELETE FROM drift_bottle_record_hides WHERE user_id=?", (user_id,))
    c.execute("DELETE FROM drift_bottle_reads WHERE user_id=?", (user_id,))
    c.execute("UPDATE drift_bottles SET origin_user_id=NULL,origin_bot_id=NULL WHERE origin_user_id=?",
              (user_id,))
