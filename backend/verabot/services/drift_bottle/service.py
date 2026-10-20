"""Drift Bottle orchestration: ownership, idempotency, leases, model boundaries."""
from __future__ import annotations

import base64
import hashlib
import json
from typing import Any, Callable

from ... import db
from ...core import ratelimit
from ...db import drift_bottle_store as store
from . import companion, visibility
from .contracts import (
    RATE_DRAW, RATE_GENERATE, RATE_PUBLISH, BottleError, Limits, MemoryPatch,
)

Model = companion.Model
_model_override: Model | None = None


def set_model_for_tests(model: Model | None) -> None:
    global _model_override
    _model_override = model


def _model() -> Model | None:
    return _model_override


def _hash(kind: str, payload: dict) -> str:
    raw = json.dumps({"kind": kind, "payload": payload}, ensure_ascii=False,
                     sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def _loads(value: str | None, fallback):
    if not value:
        return fallback
    try:
        return json.loads(value)
    except (TypeError, ValueError):
        return fallback


def _with_operation(row: dict, result: dict | None) -> dict:
    out = {"operation": store.operation_info(row)}
    if result:
        out.update(result)
    return out


def _rate(user_id: int, kind: str, limit: int):
    if not ratelimit.hit(f"drift:{kind}:{user_id}", limit, 60):
        wait = ratelimit.retry_after(f"drift:{kind}:{user_id}", 60)
        raise BottleError(429, "rate_limited", f"操作太频繁，请 {wait} 秒后再试", retry_after=wait)


def _cursor(value: str | None) -> int:
    if value is None or value == "":
        return 0
    try:
        number = int(value)
    except (TypeError, ValueError):
        raise BottleError(422, "invalid_cursor", "分页位置无效")
    if number < 0:
        raise BottleError(422, "invalid_cursor", "分页位置无效")
    return number


def _offset_cursor(value: str | None) -> int:
    if value is None or value == "":
        return 0
    try:
        raw = base64.urlsafe_b64decode(value.encode()).decode()
        prefix, number = raw.split(":", 1)
        if prefix != "v1":
            raise ValueError
        return max(0, int(number))
    except (ValueError, UnicodeDecodeError, TypeError):
        raise BottleError(422, "invalid_cursor", "分页位置无效")


def _make_cursor(offset: int) -> str:
    return base64.urlsafe_b64encode(f"v1:{offset}".encode()).decode()


def _reap(user_id: int, now: float):
    with db.tx(immediate=True) as c:
        store.expire_active(c, user_id, now)


def _encounter_detail(c, user_id: int, encounter: dict, now: float, *,
                      cursor: int = 0, page: int = 20, all_pages: bool = False) -> dict:
    return visibility.encounter_detail(c, user_id, encounter, now, cursor=cursor, page=page,
                                       all_pages=all_pages)


def _mutation(user_id: int, request_id: str, kind: str, payload: dict,
              fn: Callable, now: float, *, rate: tuple[str, int] | None = None) -> dict:
    digest = _hash(kind, payload)
    with db.tx(immediate=True) as c:
        replay = store.replay(c, user_id, request_id, digest, now)
        if replay is not None:
            row = store.operation_row(c, user_id, request_id)
            return _with_operation(row, replay)
        if rate is not None:
            _rate(user_id, rate[0], rate[1])
        result = fn(c, now)
        store.complete_operation(c, user_id, request_id, kind, digest, result, now)
        row = store.operation_row(c, user_id, request_id)
        return _with_operation(row, result)


# ---------------------------------------------------------------------------
# Reads
# ---------------------------------------------------------------------------


def state(user_id: int, now: float) -> dict:
    _reap(user_id, now)
    with db.tx() as c:
        encounter = store.active_encounter_row(c, user_id)
        detail = _encounter_detail(c, user_id, encounter, now) if encounter else None
    return {
        "server_time": now,
        "current": detail,
        "limits": Limits().model_dump(),
        "has_active_encounter": bool(detail and detail["ended_at"] is None),
    }


def get_encounter(user_id: int, encounter_id: int, cursor: str | None, now: float) -> dict:
    _reap(user_id, now)
    with db.tx() as c:
        encounter = store.encounter_row(c, user_id, encounter_id)
        return _encounter_detail(c, user_id, encounter, now, cursor=_cursor(cursor))


def records(user_id: int, bot_id: int | None, cursor: str | None, limit: int, now: float) -> dict:
    limit = max(1, min(int(limit), 50))
    offset = _offset_cursor(cursor)
    with db.tx() as c:
        encounters, releases = store.record_rows(c, user_id, bot_id)
        items = []
        for row in encounters:
            summary = visibility.record_summary(c, user_id, "encounter", row)
            summary["_sort"] = (float(row["started_at"]), int(row["id"]))
            items.append(summary)
        for row in releases:
            summary = visibility.record_summary(c, user_id, "release", row)
            summary["_sort"] = (float(row["created_at"]), int(row["id"]))
            items.append(summary)
    items.sort(key=lambda item: item.pop("_sort"), reverse=True)
    page = items[offset:offset + limit]
    next_cursor = _make_cursor(offset + limit) if offset + limit < len(items) else None
    return {"records": page, "next_cursor": next_cursor}


def record(user_id: int, record_id: str, now: float) -> dict:
    _reap(user_id, now)
    with db.tx() as c:
        return visibility.record_detail(c, user_id, record_id, now)


def operation(user_id: int, request_id: str, now: float) -> dict:
    with db.tx() as c:
        row = store.operation_row(c, user_id, request_id)
        if row is None:
            raise BottleError(404, "not_found", "这次操作不存在")
        result = _loads(row.get("result_json"), None)
        return {"operation": store.operation_info(row), "result": result}


# ---------------------------------------------------------------------------
# Bottle flow
# ---------------------------------------------------------------------------


def create_bottle(user_id: int, body, now: float) -> dict:
    request_id = body.request_id
    payload = body.model_dump()

    def run(c, moment):
        bot = store.bot_for_user(c, user_id, body.bot_id)
        bottle_id, _contribution_id = store.create_bottle_tx(
            c, user_id, bot, body.body, body.authorship, moment)
        bottle = store.bottle_row(c, bottle_id)
        return {"record": visibility.record_summary(c, user_id, "release", bottle)}

    return _mutation(user_id, request_id, "create_bottle", payload, run, now,
                     rate=("publish", RATE_PUBLISH))


def draw(user_id: int, body, now: float) -> dict:
    request_id = body.request_id
    payload = body.model_dump()

    def run(c, moment):
        bot = store.bot_for_user(c, user_id, body.bot_id)
        encounter_id, _resumed = store.draw_tx(c, user_id, bot, moment)
        if encounter_id is None:
            return {"encounter": None}
        encounter = store.encounter_row(c, user_id, encounter_id)
        return {"encounter": _encounter_detail(c, user_id, encounter, moment)}

    return _mutation(user_id, request_id, "draw", payload, run, now,
                     rate=("draw", RATE_DRAW))


def release(user_id: int, encounter_id: int, body, now: float) -> dict:
    request_id = body.request_id
    payload = body.model_dump()
    contribution = body.contribution.model_dump() if body.contribution is not None else None

    def run(c, moment):
        encounter = store.encounter_row(c, user_id, encounter_id)
        if encounter["lease_token"] != body.lease_token:
            raise BottleError(409, "invalid_lease", "这次相遇的凭证已失效，请重新载入")
        store.release_tx(c, user_id, encounter, contribution, body.expected_version, moment)
        return {"record": visibility.record_detail(c, user_id, f"encounter:{encounter_id}", moment)}

    return _mutation(user_id, request_id, "release", payload, run, now,
                     rate=("publish", RATE_PUBLISH) if contribution is not None else None)


# ---------------------------------------------------------------------------
# Visibility and moderation actions
# ---------------------------------------------------------------------------


def withdraw(user_id: int, contribution_id: int, body, now: float) -> dict:
    payload = body.model_dump()

    def run(c, moment):
        contribution = store.contribution_row(c, contribution_id)
        if contribution is None:
            raise BottleError(404, "not_found", "这条投稿不存在")
        updated = store.withdraw_tx(c, user_id, contribution, moment)
        return {"contribution": visibility.public_contribution(c, user_id, updated)}

    return _mutation(user_id, body.request_id, "withdraw", payload, run, now)


def report(user_id: int, body, now: float) -> dict:
    payload = body.model_dump()

    def run(c, moment):
        contribution = store.contribution_row(c, body.contribution_id)
        if contribution is None:
            raise BottleError(404, "not_found", "这条投稿不存在")
        item = store.report_tx(c, user_id, contribution, body.reason, moment)
        return {"report": {
            "id": int(item["id"]),
            "contribution_id": int(item["contribution_id"]),
            "state": item["state"],
            "created_at": float(item["created_at"]),
        }}

    return _mutation(user_id, body.request_id, "report", payload, run, now)


def block(user_id: int, body, now: float) -> dict:
    payload = body.model_dump()

    def run(c, moment):
        contribution = store.contribution_row(c, body.contribution_id)
        if contribution is None:
            raise BottleError(404, "not_found", "这条投稿不存在")
        store.block_tx(c, user_id, contribution, moment)
        return {"blocked": True}

    return _mutation(user_id, body.request_id, "block", payload, run, now)


def delete_record(user_id: int, record_id: str, request_id: str, now: float) -> dict:
    def run(c, moment):
        return store.delete_record_tx(c, user_id, record_id, moment)

    return _mutation(user_id, request_id, "delete_record", {"record_id": record_id}, run, now)


def delete_memory(user_id: int, record_id: str, request_id: str, now: float) -> dict:
    kind, raw = store.parse_record_id(record_id)
    if kind != "encounter":
        raise BottleError(404, "not_found", "这条记录没有回忆卡")

    def run(c, moment):
        store.encounter_row(c, user_id, raw)
        store.delete_memory(c, user_id, raw)
        return {"deleted": True}

    return _mutation(user_id, request_id, "delete_memory", {"record_id": record_id}, run, now)


def patch_memory(user_id: int, record_id: str, body: MemoryPatch, request_id: str,
                 now: float) -> dict:
    kind, raw = store.parse_record_id(record_id)
    if kind != "encounter":
        raise BottleError(404, "not_found", "这条记录没有回忆卡")
    payload = body.model_dump(exclude_none=True)

    def run(c, moment):
        store.encounter_row(c, user_id, raw)
        store.patch_memory(c, user_id, raw, payload, moment)
        return {"memory": visibility.memory_dict(c, raw)}

    return _mutation(user_id, request_id, "patch_memory",
                     {"record_id": record_id, **payload}, run, now)


# ---------------------------------------------------------------------------
# Model-backed generation
# ---------------------------------------------------------------------------


def _fail_generation(user_id: int, request_id: str, code: str, message: str,
                     now: float, encounter_id: int | None = None):
    with db.tx(immediate=True) as c:
        store.fail_operation(c, user_id, request_id, code, message, now)
        if encounter_id is not None:
            store.release_generation(c, encounter_id, request_id)


def _detail_for_result(c, user_id: int, encounter_id: int, now: float) -> dict:
    encounter = store.encounter_row(c, user_id, encounter_id)
    return _encounter_detail(c, user_id, encounter, now)


def generate_memory(user_id: int, encounter_id: int, body, now: float) -> dict:
    request_id = body.request_id
    payload = {"encounter_id": encounter_id}
    digest = _hash("memory", payload)
    _reap(user_id, now)
    with db.tx(immediate=True) as c:
        replay = store.replay(c, user_id, request_id, digest, now)
        if replay is not None:
            row = store.operation_row(c, user_id, request_id)
            return _with_operation(row, replay)
        _rate(user_id, "generate", RATE_GENERATE)
        encounter = store.encounter_row(c, user_id, encounter_id)
        if encounter["ended_at"] is None:
            raise BottleError(409, "memory_before_end", "先把这次相遇收好，再整理共同回忆")
        memory = store.memory_row(c, encounter_id)
        if memory is not None and memory["owner_edited"]:
            result = {"memory": visibility.memory_dict(c, encounter_id)}
            store.complete_operation(c, user_id, request_id, "memory", digest, result, now)
            row = store.operation_row(c, user_id, request_id)
            return _with_operation(row, result)
        turns = store.turns_for(c, encounter_id)
        has_chat = any(row["kind"] == "chat" for row in turns)
        if not has_chat:
            store.ensure_fact_memory(c, user_id, encounter_id, encounter, now)
            result = {"memory": visibility.memory_dict(c, encounter_id)}
            store.complete_operation(c, user_id, request_id, "memory", digest, result, now)
            row = store.operation_row(c, user_id, request_id)
            return _with_operation(row, result)
        store.claim_generation(c, encounter_id, request_id, f"user:{user_id}", now)
        store.begin_operation(c, user_id, request_id, "memory", digest, now)
        bot = None if encounter["bot_id"] is None else store.bot_for_user(c, user_id, encounter["bot_id"])
        contributions = visibility.readable_bodies(c, user_id, encounter["bottle_id"], encounter["read_limit"])
    if bot is None:
        _fail_generation(user_id, request_id, "bot_deleted", "这位 Bot 已被删除，无法继续生成", now, encounter_id)
        raise BottleError(409, "bot_deleted", "这位 Bot 已被删除，无法继续生成")
    try:
        title, summary = _run_async(companion.memory(bot, contributions, turns, _model()))
    except companion.GenerationError as error:
        _fail_generation(user_id, request_id, error.code, error.message, now, encounter_id)
        raise BottleError(502, error.code, error.message)
    except Exception:
        _fail_generation(user_id, request_id, "generation_failed", "这次回忆整理没有顺利完成，可以稍后重试",
                         now, encounter_id)
        raise BottleError(502, "generation_failed", "这次回忆整理没有顺利完成，可以稍后重试")
    with db.tx(immediate=True) as c:
        try:
            encounter = store.encounter_row(c, user_id, encounter_id)
        except BottleError:
            store.fail_operation(c, user_id, request_id, "stale_target", "这次记录已被删除", now)
            store.release_generation(c, encounter_id, request_id)
            c.commit()
            raise BottleError(409, "stale_target", "这次记录已被删除")
        if encounter["bot_id"] is None:
            store.fail_operation(c, user_id, request_id, "bot_deleted", "这位 Bot 已被删除", now)
            store.release_generation(c, encounter_id, request_id)
            c.commit()
            raise BottleError(409, "bot_deleted", "这位 Bot 已被删除，无法继续生成")
        memory = store.memory_row(c, encounter_id)
        if memory is not None and memory["owner_edited"]:
            pass  # Never overwrite the owner's edit.
        else:
            source_turn_ids = [int(row["id"]) for row in turns]
            source_ids = [int(row["id"]) for row in contributions]
            store.save_generated_memory(c, user_id, encounter_id, title, summary,
                                        source_turn_ids, source_ids, now)
        result = {"memory": visibility.memory_dict(c, encounter_id)}
        store.complete_operation(c, user_id, request_id, "memory", digest, result, now)
        store.release_generation(c, encounter_id, request_id)
        row = store.operation_row(c, user_id, request_id)
        return _with_operation(row, result)


def _run_async(coro):
    """Companion functions are async; the service is sync and runs in a threadpool."""
    import asyncio
    try:
        asyncio.get_running_loop()
    except RuntimeError:
        return asyncio.run(coro)
    # A running loop in the same thread (TestClient can do this) needs a worker thread.
    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor(max_workers=1) as pool:
        return pool.submit(asyncio.run, coro).result()


def turns(user_id: int, encounter_id: int, body, now: float) -> dict:
    request_id = body.request_id
    payload = body.model_dump()
    digest = _hash("turn", payload)
    _reap(user_id, now)
    with db.tx(immediate=True) as c:
        replay = store.replay(c, user_id, request_id, digest, now)
        if replay is not None:
            row = store.operation_row(c, user_id, request_id)
            return _with_operation(row, replay)
        _rate(user_id, "generate", RATE_GENERATE)
        encounter = store.encounter_row(c, user_id, encounter_id)
        if body.kind == "opening":
            if body.quiet:
                store.set_quiet(c, encounter_id, now)
                encounter = store.encounter_row(c, user_id, encounter_id)
                result = {"encounter": _encounter_detail(c, user_id, encounter, now),
                          "turn": None, "draft": None}
                store.complete_operation(c, user_id, request_id, "turn", digest, result, now)
                row = store.operation_row(c, user_id, request_id)
                return _with_operation(row, result)
            existing = store.turn_by_event(c, encounter_id, "opening")
            if existing is not None:
                result = {"encounter": _encounter_detail(c, user_id, encounter, now),
                          "turn": _turn_dict(existing), "draft": None}
                store.complete_operation(c, user_id, request_id, "turn", digest, result, now)
                row = store.operation_row(c, user_id, request_id)
                return _with_operation(row, result)
            if encounter["ended_at"] is not None:
                raise BottleError(409, "opening_only_active", "这次相遇已经结束，可以继续聊，但不会重新开场")
        elif body.kind == "draft" and encounter["ended_at"] is not None:
            raise BottleError(409, "encounter_ended", "这次相遇已经结束，不能再准备公开留言")
        if encounter["bot_id"] is None:
            raise BottleError(409, "bot_deleted", "这位 Bot 已被删除，无法继续生成")
        if body.kind == "chat":
            store.append_turn_tx(c, encounter_id, role="user", kind="chat", content=body.text,
                                 request_id=request_id, event_key=f"user:{request_id}", now=now)
        store.claim_generation(c, encounter_id, request_id, f"user:{user_id}", now)
        store.begin_operation(c, user_id, request_id, "turn", digest, now)
        bot = store.bot_for_user(c, user_id, encounter["bot_id"])
        contributions = visibility.readable_bodies(c, user_id, encounter["bottle_id"], encounter["read_limit"])
        history = store.turns_for(c, encounter_id)
    if body.kind == "chat":
        history = [row for row in history if not (row["request_id"] == request_id and row["role"] == "user")]
    try:
        if body.kind == "opening":
            text = _run_async(companion.opening(bot, contributions, history, _model()))
        elif body.kind == "chat":
            text = _run_async(companion.chat(bot, contributions, history, body.text, _model()))
        else:
            text = _run_async(companion.draft(bot, contributions, history, body.text, _model()))
    except companion.GenerationError as error:
        _fail_generation(user_id, request_id, error.code, error.message, now, encounter_id)
        raise BottleError(502, error.code, error.message)
    except Exception:
        _fail_generation(user_id, request_id, "generation_failed", "Bot 这次没有顺利回应，可以重试或自己写",
                         now, encounter_id)
        raise BottleError(502, "generation_failed", "Bot 这次没有顺利回应，可以重试或自己写")
    with db.tx(immediate=True) as c:
        try:
            fresh = store.encounter_row(c, user_id, encounter_id)
        except BottleError:
            store.fail_operation(c, user_id, request_id, "stale_target", "这次相遇已被删除", now)
            store.release_generation(c, encounter_id, request_id)
            c.commit()
            raise BottleError(409, "stale_target", "这次相遇已被删除")
        if fresh["bot_id"] is None:
            store.fail_operation(c, user_id, request_id, "bot_deleted", "这位 Bot 已被删除", now)
            store.release_generation(c, encounter_id, request_id)
            c.commit()
            raise BottleError(409, "bot_deleted", "这位 Bot 已被删除，无法继续生成")
        if body.kind == "opening":
            if fresh["ended_at"] is not None:
                store.fail_operation(c, user_id, request_id, "stale_target", "这次相遇已经结束", now)
                store.release_generation(c, encounter_id, request_id)
                c.commit()
                raise BottleError(409, "stale_target", "这次相遇已经结束，不会重新开场")
            turn = store.append_turn_tx(c, encounter_id, role="bot", kind="opening", content=text,
                                        request_id=request_id, event_key="opening", now=now)
        elif body.kind == "chat":
            turn = store.append_turn_tx(c, encounter_id, role="bot", kind="chat", content=text,
                                        request_id=request_id, event_key=f"bot:{request_id}", now=now)
        else:
            turn = store.append_turn_tx(c, encounter_id, role="bot", kind="draft", content=text,
                                        request_id=request_id, event_key=f"draft:{request_id}", now=now)
        result = {"encounter": _encounter_detail(c, user_id, fresh, now),
                  "turn": None if body.kind == "draft" else _turn_dict(turn),
                  "draft": text if body.kind == "draft" else None}
        store.complete_operation(c, user_id, request_id, "turn", digest, result, now)
        store.release_generation(c, encounter_id, request_id)
        row = store.operation_row(c, user_id, request_id)
        return _with_operation(row, result)


def draft_suggestion(user_id: int, body, now: float) -> dict:
    request_id = body.request_id
    payload = body.model_dump()
    digest = _hash("draft_suggestion", payload)
    with db.tx(immediate=True) as c:
        replay = store.replay(c, user_id, request_id, digest, now)
        if replay is not None:
            row = store.operation_row(c, user_id, request_id)
            return _with_operation(row, replay)
        _rate(user_id, "generate", RATE_GENERATE)
        bot = store.bot_for_user(c, user_id, body.bot_id)
        store.begin_operation(c, user_id, request_id, "draft_suggestion", digest, now)
    try:
        text = _run_async(companion.draft_for_new_bottle(bot, body.body, _model()))
    except companion.GenerationError as error:
        _fail_generation(user_id, request_id, error.code, error.message, now)
        raise BottleError(502, error.code, error.message)
    except Exception:
        _fail_generation(user_id, request_id, "generation_failed", "Bot 这次没有顺利回应，可以重试或自己写", now)
        raise BottleError(502, "generation_failed", "Bot 这次没有顺利回应，可以重试或自己写")
    with db.tx(immediate=True) as c:
        try:
            store.bot_for_user(c, user_id, body.bot_id)
        except BottleError:
            store.fail_operation(c, user_id, request_id, "bot_deleted", "这位 Bot 已被删除", now)
            c.commit()
            raise BottleError(409, "bot_deleted", "这位 Bot 已被删除，无法继续生成")
        result = {"draft": text, "authorship": "bot_draft"}
        store.complete_operation(c, user_id, request_id, "draft_suggestion", digest, result, now)
        row = store.operation_row(c, user_id, request_id)
        return _with_operation(row, result)


def _turn_dict(row: dict) -> dict:
    return {
        "id": int(row["id"]),
        "role": row["role"],
        "kind": row["kind"],
        "content": row["content"],
        "created_at": float(row["created_at"]),
    }
