"""受权限约束的委派记忆选择与限长渲染。"""
from .. import db
from ..core import config
from ..db import memory_store
from ..services.memory import repository as repo
from ..services.memory.policy import render_safe


def _visible(memory: dict, bot: dict) -> bool:
    access = bot.get("memory_access") or "none"
    if access == "none":
        return False
    if memory["scope"] == "bot":
        return memory.get("bot_id") == bot["id"]
    return memory["scope"] == "global" and access == "bot_and_global"


def _renderable(memory: dict) -> bool:
    return memory.get("status") == "active" and memory.get("sensitivity", "normal") == "normal" \
        and memory.get("scope") in ("bot", "global")


def select(user_id: int, source_bot: dict, target_bot: dict, memory_ids=None) -> tuple[list[dict], list[int], list[int], int]:
    """返回 (供 prompt 使用的安全记忆, 显式共享 ID, 自动附加 ID, 拒绝数量)。"""
    requested = memory_ids if isinstance(memory_ids, list) else []
    candidates = []
    rejected = (1 if memory_ids is not None and not isinstance(memory_ids, list) else 0) \
        + max(0, len(requested) - config.MAX_DELEGATION_MEMORY_IDS)
    seen = set()
    for mid in requested[:config.MAX_DELEGATION_MEMORY_IDS]:
        if not isinstance(mid, int) or isinstance(mid, bool) or mid <= 0 or mid in seen:
            rejected += 1
            continue
        seen.add(mid)
        candidates.append(mid)

    with db.tx() as c:
        selected = repo.query(c, user_id, f"m.id IN ({','.join('?' * len(candidates))})" if candidates else "0",
                              tuple(candidates), limit=len(candidates) or 1) if candidates else []
        selected_by_id = {memory["id"]: memory for memory in selected}
        accepted = []
        for mid in candidates:
            memory = selected_by_id.get(mid)
            if memory is None:
                continue
            if (_renderable(memory) and _visible(memory, source_bot) and _visible(memory, target_bot)):
                accepted.append(memory)
        rejected += len(candidates) - len(accepted)

        access = target_bot.get("memory_access") or "none"
        if access == "none":
            automatic = []
        else:
            clauses = ["m.user_id=?", "m.status='active'", "m.sensitivity='normal'",
                       "m.type IN ('style','profile')", "m.scope IN ('bot','global')"]
            params = [user_id]
            visible = ["(m.scope='bot' AND m.bot_id=?)"]
            params.append(target_bot["id"])
            if access == "bot_and_global":
                visible.append("m.scope='global'")
            clauses.append("(" + " OR ".join(visible) + ")")
            automatic = memory_store.query(c, user_id, " AND ".join(clauses[1:]), tuple(params[1:]),
                                           order="CASE m.type WHEN 'style' THEN 0 ELSE 1 END, m.updated_at DESC, m.id DESC",
                                           limit=config.MAX_DELEGATION_AUTO_MEMORIES)

    selected_ids = {m["id"] for m in accepted}
    automatic = [m for m in automatic if m["id"] not in selected_ids]
    automatic = automatic[:config.MAX_DELEGATION_AUTO_MEMORIES]
    output, shared_ids, target_ids, used_chars = [], [], [], 0
    groups = ((accepted, "selected", shared_ids), (automatic, "target", target_ids))
    for memories, origin, ids in groups:
        for memory in memories:
            if used_chars >= config.MAX_DELEGATION_MEMORY_CHARS:
                if origin == "selected":
                    rejected += 1
                continue
            text = render_safe(memory.get("content") or "", limit=config.MAX_DELEGATION_MEMORY_CHARS - used_chars)
            if not text:
                if origin == "selected":
                    rejected += 1
                continue
            output.append({"id": memory["id"], "type": memory["type"], "scope": memory["scope"],
                           "content": text, "origin": origin})
            ids.append(memory["id"])
            used_chars += len(text)
    return output, shared_ids, target_ids, rejected
