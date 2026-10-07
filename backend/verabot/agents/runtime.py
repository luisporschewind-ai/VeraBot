"""Agent 执行循环（Runtime）：Prompt 组装 → LLM（流式）→ Tool Calling → 回填结果 → 继续，直至给出最终回答。"""
import asyncio
import json
import logging

from .. import db
from ..core.config import EMPTY_REPLY_RETRIES, HISTORY_WINDOW, MAX_TOOL_ROUNDS
from ..services import llm, memory
from ..services.memory import jobs as memory_jobs
from ..services.memory import style as memory_style
from ..services.attachments import repo as attachments
from ..services.attachments import vision
from ..tools.registry import ToolContext, TurnState
from .context import delegation_message
from .prompts import system_prompt
from .tool_router import dispatch, schemas_for, trace_meta

log = logging.getLogger("verabot.agent")
EMPTY_REPLY_MSG = "模型没有返回内容（已自动重试），请稍后再试或换个说法"

# SSE `status` 事件（v6 后新增，向后兼容：旧客户端忽略未知事件）。payload 固定 5 个键：
#   phase      "recalling" 召回记忆 / 准备上下文（depth 0）；"thinking" 被委派 Bot 等待模型；"tool" 被委派 Bot 调用工具
#   depth      0 = 用户直接对话的 Bot；≥1 = 委派链上的 Bot
#   bot_name   正在工作的 Bot 昵称
#   tool       phase = "tool" 时的工具名，否则 null
#   parent_id  depth ≥ 1 时为外层 tool_start 的 id（客户端据此挂到对应的 ask_bot 上），否则 null
# 契约测试：scripts/test/status_event_test.py（与 iOS VeraBotCore `ChatStatus` 的 CodingKeys / Phase 对照）。
STATUS_PHASES = ("recalling", "thinking", "tool")
STATUS_KEYS = ("phase", "depth", "bot_name", "tool", "parent_id")


def status_data(phase: str, *, depth: int, bot_name: str | None, tool: str | None = None,
                parent_id: str | None = None) -> dict:
    assert phase in STATUS_PHASES
    return {"phase": phase, "depth": depth, "bot_name": bot_name, "tool": tool, "parent_id": parent_id}


def _emit_status(ctx: ToolContext, phase: str, tool: str | None = None):
    """被委派 Bot 的进度：放进外层队列，由 run_chat 转成 SSE status 事件。没有队列时什么也不做。"""
    q = ctx.turn.status_queue
    if q is not None:
        q.put_nowait(status_data(phase, depth=ctx.depth, bot_name=ctx.bot.get("name"), tool=tool,
                                 parent_id=ctx.turn.parent_id))


async def _run_tool_streaming(ctx: ToolContext, tc: dict):
    """执行一个外层工具调用，期间把委派树里产生的 status 实时转发；最后产出 ("result", dict)。"""
    queue: asyncio.Queue = asyncio.Queue()
    ctx.turn.status_queue, ctx.turn.parent_id = queue, tc["id"]
    task = asyncio.ensure_future(dispatch(ctx, tc["name"], tc["arguments"], call_id=tc.get("id")))
    try:
        while not task.done() or not queue.empty():
            if not queue.empty():
                yield ("status", queue.get_nowait())
                continue
            getter = asyncio.ensure_future(queue.get())
            done, _ = await asyncio.wait({task, getter}, return_when=asyncio.FIRST_COMPLETED)
            if getter in done:
                yield ("status", getter.result())
            else:
                getter.cancel()
        yield ("result", task.result())
    finally:
        if not task.done():
            task.cancel()
        ctx.turn.status_queue, ctx.turn.parent_id = None, None


def _tool_content(name: str, result: dict) -> str:
    """工具结果 → tool 消息。内置工具截到 6000 字；MCP 结果已在 sanitize 里截断并包裹，
    不能再按字符截，否则会切掉 </untrusted_tool_result> 结束标记。"""
    text = json.dumps(result, ensure_ascii=False)
    return text if name.startswith("mcp__") else text[:6000]


def _add_usage(total: dict, u: dict):
    for k in ("prompt_tokens", "completion_tokens", "total_tokens"):
        total[k] = total.get(k, 0) + int(u.get(k) or 0)


def _history(user_id: int, bot_id: int) -> tuple[list[dict], dict | None]:
    """历史消息 → LLM messages。曾调用工具的回复按真实协议还原为
    assistant(tool_calls) → tool(result) → assistant(content)，
    避免模型从纯文本历史中"学会"不调用工具就声称已查询 / 已咨询。
    带图的用户消息只放文字描述（按需召回）；同时返回窗口里最近一张图（没有则 None）。"""
    out = []
    recent = db.recent_messages(user_id, bot_id, HISTORY_WINDOW)
    att_map = attachments.for_messages(user_id, [m["id"] for m in recent if m["role"] == "user"])
    for m in recent:
        traces = json.loads(m["traces"]) if m.get("traces") else []
        if m["role"] == "assistant" and traces:
            calls = [t for t in traces if t.get("id") and t.get("name")]
            if calls:
                out.append({"role": "assistant", "content": None, "tool_calls": [
                    {"id": t["id"], "type": "function",
                     "function": {"name": t["name"], "arguments": json.dumps(t.get("args") or {}, ensure_ascii=False)}}
                    for t in calls]})
                for t in calls:
                    out.append({"role": "tool", "tool_call_id": t["id"],
                                "content": json.dumps(t.get("result") or {}, ensure_ascii=False)[:1500]})
        content = vision.history_text(m["content"], att_map[m["id"]]) if m["id"] in att_map else m["content"]
        out.append({"role": m["role"], "content": content})
    latest = max((r for rs in att_map.values() for r in rs), key=lambda r: (r["message_id"], r["created_at"]),
                 default=None)
    return out, latest


MEMORY_TOOLS = ("remember", "forget_memory")


def _redact_memory_trace(trace: dict) -> dict:
    """记忆工具的 trace 会写入 messages.traces 并下发客户端：凭据类被拦截时隐藏参数原文；
    敏感（健康 / 财务）提议的正文只以密文保存在 memories，trace 里换成占位，客户端按 memory_id 拉取明文。"""
    result = trace.get("result") or {}
    args = dict(trace.get("args") or {})
    if result.get("code") in ("sensitive_credential", "sensitive_category", "blocked_content") or result.get("sensitive"):
        if "content" in args:
            args["content"] = "（已隐藏）"
        if result.get("sensitive"):
            result = {**result, "content": "（敏感内容，已加密）"}
            if "target_content" in result:
                result["target_content"] = "（敏感内容，已加密）"
    return {**trace, "args": args, "result": result}


def _memory_query(history: list[dict], user_text: str) -> str:
    """召回查询文本：本轮用户消息 + 最近 2 条用户消息。"""
    recent = [m["content"] for m in history if m.get("role") == "user" and m.get("content")][-2:]
    return "\n".join([*recent, user_text])


async def run_chat(user_id: int, bot: dict, user_text: str, attachment_ids: list[str] | None = None):
    """流式对话主循环，产出给前端的 SSE 事件 dict。attachment_ids 由路由预先校验（check_pending）。"""
    history, latest_image = _history(user_id, bot["id"])
    memory_on = memory.enabled_for(user_id)
    if memory_on:
        yield {"event": "status", "data": status_data("recalling", depth=0, bot_name=bot.get("name"))}
    rec = memory.recall(user_id, bot, _memory_query(history, user_text)) if memory_on else memory.EMPTY
    user_mid = db.add_message(user_id, bot["id"], "user", user_text)
    new_images = attachments.attach(user_id, bot["id"], list(attachment_ids or []), user_mid)
    turn = TurnState()
    images = new_images or ([latest_image] if latest_image and vision.wants_recall(user_text) else [])
    if images:
        turn.image_ids, turn.image_tainted = [r["id"] for r in images], True
        turn.recalls = 0 if new_images else 1   # 关键词兜底也算本轮的 1 次召回
    memory_tools = memory_on and (bot.get("memory_access") or "none") != "none"
    system = system_prompt(user_id, bot, memory_block=rec.block, memory_tools=memory_tools)
    if images or latest_image:
        system += vision.PROMPT_RULES
    messages = [{"role": "system", "content": system}, *history]
    ctx = ToolContext(user_id=user_id, bot=bot, depth=0, chain=[], turn=turn, user_message_id=user_mid)
    tools = schemas_for(bot, 0, memory_on, user_id) + vision.schema_for_history(latest_image is not None)
    usage_total: dict = {}
    traces: list = []
    answer = ""
    errored = False
    style_trace = None
    try:
        messages.append({"role": "user", "content": vision.user_content(user_text, images)})
        for _round in range(MAX_TOOL_ROUNDS + 1):
            use_tools = (tools or None) if _round < MAX_TOOL_ROUNDS else None
            for attempt in range(EMPTY_REPLY_RETRIES + 1):
                round_text, tool_calls, finish = "", [], None
                async for kind, val in llm.stream_chat(messages, use_tools):
                    if kind == "delta":
                        round_text += val
                        answer += val
                        yield {"event": "delta", "data": {"text": val}}
                    elif kind == "tool_calls":
                        tool_calls = val
                    elif kind == "usage":
                        _add_usage(usage_total, val)
                    elif kind == "finish":
                        finish = val
                log.info("llm round=%s attempt=%s bot=%s finish_reason=%s text_len=%s tool_calls=%s",
                         _round, attempt, bot["id"], finish, len(round_text), len(tool_calls))
                if round_text.strip() or tool_calls:
                    break
                log.warning("empty LLM reply (finish_reason=%s) bot=%s round=%s attempt=%s", finish, bot["id"], _round, attempt)
            if not tool_calls:
                break
            messages.append({"role": "assistant", "content": round_text or None,
                             "tool_calls": [{"id": tc["id"], "type": "function",
                                             "function": {"name": tc["name"], "arguments": tc["arguments"]}}
                                            for tc in tool_calls]})
            for tc in tool_calls:
                try:
                    args = json.loads(tc["arguments"] or "{}")
                except json.JSONDecodeError:
                    args = {"_raw": tc["arguments"]}
                yield {"event": "tool_start", "data": {"id": tc["id"], "name": tc["name"], "args": args,
                                                       **trace_meta(user_id, tc["name"])}}
                result: dict = {}
                async for kind, val in _run_tool_streaming(ctx, tc):
                    if kind == "status":
                        yield {"event": "status", "data": val}
                    else:
                        result = val
                if result.get("status") == "pending_confirmation" and result.get("action_id"):
                    from ..services.actions import sse_payload
                    yield {"event": "confirmation_required", "data": sse_payload(result)}
                trace = {"id": tc["id"], "name": tc["name"], "args": args, "result": result}
                if tc["name"] in MEMORY_TOOLS:
                    trace = _redact_memory_trace(trace)
                traces.append(trace)
                yield {"event": "tool_result", "data": trace}
                messages.append({"role": "tool", "tool_call_id": tc["id"],
                                 "content": _tool_content(tc["name"], result)})
            if turn.pending_images:   # view_image：原图作为额外 user 消息附上
                messages.append(vision.recall_message(turn.pending_images))
                turn.image_ids += [r["id"] for r in turn.pending_images]
                turn.image_tainted, turn.pending_images = True, []
        if not answer.strip():
            errored = True
            yield {"event": "error", "data": {"message": EMPTY_REPLY_MSG, "code": "empty_reply"}}
    except llm.LLMError as e:
        errored = True
        yield {"event": "error", "data": vision.vision_error(e) if turn.image_ids else {"message": str(e)}}
    except FileNotFoundError:   # 图片文件已被删除（410 语义）
        errored = True
        yield {"event": "error", "data": {"message": attachments.GONE_MESSAGE, "code": "attachment_gone"}}
    except Exception as e:  # 网络等异常
        errored = True
        yield {"event": "error", "data": {"message": f"{type(e).__name__}: {e}"}}
    finally:
        # ask_bot 子调用用量已由工具单独记账；这里只记本 Bot 的主调用
        db.log_usage(user_id, bot["id"], "chat", usage_total)
        if memory_tools:
            cue = memory_style.match_style(user_text)
            if cue:
                proposal = memory.propose_style(user_id, bot, cue, user_message_id=user_mid)
                if proposal and proposal.get("status") == "proposed":
                    style_trace = memory_style.trace_for(proposal)
                    traces.append(style_trace)
        stored = answer if answer.strip() else ("⚠️ " + EMPTY_REPLY_MSG if errored else "（无回复）")
        mid = db.add_message(user_id, bot["id"], "assistant", stored, traces or None, memory_ids=rec.ids or None)
        memory.mark_used(user_id, rec.ids)
        if memory_tools:
            memory_jobs.enqueue(user_id, bot["id"], kind="summarize", after_message_id=mid)
    if style_trace:
        yield {"event": "tool_result", "data": style_trace}
    # user_message_id：本轮用户消息的 id（新增字段，旧客户端忽略），客户端据此可立即删除刚发出的消息
    yield {"event": "done", "data": {"message_id": mid, "user_message_id": user_mid, "usage": usage_total, "memory_ids": rec.ids}}
    if new_images and not errored:   # 首次看图后生成描述（按需召回用），放在 done 之后不拖慢回复
        await vision.ensure_captions(user_id, bot["id"], new_images)


async def run_once(user_id: int, bot: dict, question: str, shared_context: str,
                   from_bot: dict, depth: int, chain: list | None = None, turn: TurnState | None = None
                   ) -> tuple[str, dict, str]:
    """被委派 Bot 的非流式执行：独立上下文（Context isolation）——只含 question + shared_context + 发起方公开资料，
    绝不携带任何一方的聊天历史。仅可使用目标 Bot 自身白名单内、且深度允许的工具。返回 (answer, usage, payload)。"""
    user_msg = delegation_message(from_bot, question, shared_context)
    images = [r for r in (attachments.get(user_id, i) for i in (turn.image_ids if turn else [])) if r]
    system = system_prompt(user_id, bot, delegated_by=from_bot, depth=depth) + (vision.PROMPT_RULES if images else "")
    messages = [{"role": "system", "content": system},
                {"role": "user", "content": vision.user_content(user_msg, images)}]   # 委派：本轮图片按引用转给对方
    ctx = ToolContext(user_id=user_id, bot=bot, depth=depth, chain=list(chain or []), turn=turn or TurnState())
    tools = schemas_for(bot, depth, False, user_id)
    usage_total: dict = {}
    for _round in range(MAX_TOOL_ROUNDS + 1):
        use_tools = (tools or None) if _round < MAX_TOOL_ROUNDS else None
        for attempt in range(EMPTY_REPLY_RETRIES + 1):
            _emit_status(ctx, "thinking")
            msg, usage = await llm.complete(messages, use_tools)
            _add_usage(usage_total, usage)
            calls = msg.get("tool_calls") or []
            content = (msg.get("content") or "").strip()
            if content or calls:
                break
            log.warning("empty delegated reply (finish_reason=%s) bot=%s attempt=%s", msg.get("_finish_reason"), bot["id"], attempt)
        if not calls:
            return content or f"（{bot['name']} 暂时没有给出答复）", usage_total, user_msg
        messages.append({"role": "assistant", "content": msg.get("content"), "tool_calls": calls})
        for tc in calls:
            _emit_status(ctx, "tool", tool=tc["function"]["name"])
            result = await dispatch(
                ctx, tc["function"]["name"], tc["function"].get("arguments", "{}"), call_id=tc.get("id"),
            )
            messages.append({"role": "tool", "tool_call_id": tc["id"],
                             "content": _tool_content(tc["function"]["name"], result)})
    return f"（{bot['name']} 暂时没有给出答复）", usage_total, user_msg
