"""委派（Delegation）：ask_bot 工具——向同一用户的另一个 Bot 咨询 / 委派。

上下文隔离 (Context Isolation)：被咨询的 Bot 看不到发起方的对话历史，只收到
  question + 发起方显式传入的 shared_context（长度受限）+ 发起方的公开资料（名称 / 人设摘要）。
被咨询方的回答不会写入其自身聊天记录，而是完整记录在 delegations 表中供审计（含实际发送的 payload 与 token）。

服务端护栏 (Guardrails，均不依赖 prompt)：见 guardrails.py（白名单 / accept / 环路 / 单轮上限 / 预算）
与 permissions.py（最大深度）。上下文隔离规则见 context.py。
"""
import logging

from .. import db
from ..core.config import MAX_DELEGATION_MEMORY_IDS, MAX_SHARED_CONTEXT
from ..db import delegation_store
from ..tools.registry import ToolContext, tool
from .context import clean_question, limit_shared_context
from .delegation_memory import select as select_shared_memories
from .guardrails import allowed_target_names, check_delegation

log = logging.getLogger("verabot.delegation")


def _find_bot(user_id: int, name: str):
    """按昵称查找本人的 Bot：优先精确匹配（忽略大小写）；模糊匹配仅在结果唯一、且较短一方 ≥2 字时生效，
    避免「BobBot」被误匹配到「B」这类错投。"""
    bots = db.list_bots(user_id)  # 仅查询当前用户，天然隔离
    n = (name or "").strip().lower()
    if not n:
        return None
    for b in bots:
        if b["name"].lower() == n:
            return b
    fuzzy = [b for b in bots if min(len(n), len(b["name"])) >= 2 and (n in b["name"].lower() or b["name"].lower() in n)]
    return fuzzy[0] if len(fuzzy) == 1 else None


def _record(ctx: ToolContext, target: dict | None, question: str, shared: str, *, status: str, reason: str = "",
            answer: str = "", payload: str = "", truncated: bool = False, usage: dict | None = None) -> int:
    u = usage or {}
    return delegation_store.insert(
        user_id=ctx.user_id, from_bot_id=ctx.bot["id"], to_bot_id=target["id"] if target else 0, question=question,
        shared_context=shared, answer=answer, status=status, reason=reason, depth=ctx.depth + 1, payload=payload,
        shared_truncated=int(truncated), prompt_tokens=int(u.get("prompt_tokens") or 0),
        completion_tokens=int(u.get("completion_tokens") or 0), total_tokens=int(u.get("total_tokens") or 0))


def _reject(ctx: ToolContext, target, question, shared, reason: str, message: str, **extra):
    log.warning("delegation rejected: user=%s from=%s to=%s reason=%s", ctx.user_id, ctx.bot["id"],
                target["id"] if target else None, reason)
    did = _record(ctx, target, question, shared, status="rejected", reason=reason)
    db.audit(ctx.user_id, ctx.bot["id"], "delegation_rejected",
             {"to": target["name"] if target else None, "reason": reason, "delegation_id": did})
    return {"error": message, "code": reason, "delegation_id": did, **extra}


@tool("ask_bot", "向用户的另一个 Bot 咨询或委派子任务。对方看不到当前对话；必要时可显式共享可访问的记忆 ID，"
      "服务器会按目标 Bot 权限过滤，并自动附加目标 Bot 可见的相关风格 / 资料。",
      {"type": "object", "properties": {
          "bot_name": {"type": "string", "description": "目标 Bot 的昵称"},
          "question": {"type": "string", "description": "要咨询的问题 / 子任务"},
          "shared_context": {"type": "string", "description": f"显式共享给对方的必要背景（可选，最多 {MAX_SHARED_CONTEXT} 字）"},
          "memory_ids": {"type": "array", "items": {"type": "integer", "minimum": 1}, "uniqueItems": True,
                         "maxItems": MAX_DELEGATION_MEMORY_IDS, "description": "可选；显式共享的记忆 ID，服务端仍会校验所有权、状态、敏感度和双方权限"}},
       "required": ["bot_name", "question"]},
      delegation=True)
async def ask_bot(ctx: ToolContext, bot_name: str, question: str, shared_context: str = "", memory_ids=None):
    from .runtime import run_once  # 避免循环导入

    question = clean_question(question)
    shared, truncated = limit_shared_context(shared_context)
    target = _find_bot(ctx.user_id, bot_name)
    if target is None:
        return {"error": f"找不到名为「{bot_name}」的 Bot", "available_bots": allowed_target_names(ctx)}
    rejection = check_delegation(ctx, target)
    if rejection:
        return _reject(ctx, target, question, shared, rejection.reason, rejection.message, **rejection.extra)
    shared_memories, shared_ids, target_memory_ids, filtered_count = select_shared_memories(
        ctx.user_id, ctx.bot, target, memory_ids)
    ctx.turn.delegations += 1

    answer, usage, payload = await run_once(ctx.user_id, target, question, shared, from_bot=ctx.bot,
                                            depth=ctx.depth + 1, chain=[*ctx.chain, ctx.bot["id"]], turn=ctx.turn,
                                            shared_memories=shared_memories)
    db.log_usage(ctx.user_id, target["id"], "delegation", usage)
    did = _record(ctx, target, question, shared, status="ok", answer=answer, payload=payload,
                  truncated=truncated, usage=usage)
    out = {"from_bot": ctx.bot["name"], "to_bot": target["name"], "to_avatar": target["avatar"],
           "question": question, "shared_context": shared, "shared_truncated": truncated,
           "answer": answer, "delegation_id": did, "tokens": int(usage.get("total_tokens") or 0),
           "shared_memory_ids": shared_ids, "target_memory_ids": target_memory_ids}
    if filtered_count:
        db.audit(ctx.user_id, ctx.bot["id"], "delegation_memory_filtered",
                 {"delegation_id": did, "to": target["id"], "shared_ids": shared_ids,
                  "target_memory_ids": target_memory_ids, "rejected_count": filtered_count})
    delegated_attachment_ids = list(dict.fromkeys([*ctx.turn.image_ids, *ctx.turn.file_ids]))
    if delegated_attachment_ids:   # 附件按引用传递；文件正文不写入委派审计
        out["attachment_ids"] = delegated_attachment_ids
        db.audit(ctx.user_id, ctx.bot["id"], "delegation_attachments",
                 {"delegation_id": did, "to": target["id"], "attachment_ids": out["attachment_ids"]})
    return out
