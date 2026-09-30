"""Agent 执行循环（Runtime）：Prompt 组装 → LLM（流式）→ Tool Calling → 回填结果 → 继续，直至给出最终回答。"""
import json
import logging

from .. import db
from ..core.config import EMPTY_REPLY_RETRIES, HISTORY_WINDOW, MAX_TOOL_ROUNDS
from ..services import llm
from ..tools.registry import ToolContext, TurnState, run_tool
from .context import delegation_message
from .permissions import get_schemas
from .prompts import system_prompt

log = logging.getLogger("verabot.agent")
EMPTY_REPLY_MSG = "模型没有返回内容（已自动重试），请稍后再试或换个说法"


def _add_usage(total: dict, u: dict):
    for k in ("prompt_tokens", "completion_tokens", "total_tokens"):
        total[k] = total.get(k, 0) + int(u.get(k) or 0)


def _history(user_id: int, bot_id: int) -> list[dict]:
    """历史消息 → LLM messages。曾调用工具的回复按真实协议还原为
    assistant(tool_calls) → tool(result) → assistant(content)，
    避免模型从纯文本历史中"学会"不调用工具就声称已查询 / 已咨询。"""
    out = []
    for m in db.recent_messages(user_id, bot_id, HISTORY_WINDOW):
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
        out.append({"role": m["role"], "content": m["content"]})
    return out


async def run_chat(user_id: int, bot: dict, user_text: str):
    """流式对话主循环，产出给前端的 SSE 事件 dict。"""
    history = _history(user_id, bot["id"])
    db.add_message(user_id, bot["id"], "user", user_text)
    messages = [{"role": "system", "content": system_prompt(user_id, bot)}, *history,
                {"role": "user", "content": user_text}]
    ctx = ToolContext(user_id=user_id, bot=bot, depth=0, chain=[], turn=TurnState())
    tools = get_schemas(bot, 0)
    usage_total: dict = {}
    traces: list = []
    answer = ""
    errored = False
    try:
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
                yield {"event": "tool_start", "data": {"id": tc["id"], "name": tc["name"], "args": args}}
                result = await run_tool(ctx, tc["name"], tc["arguments"])
                trace = {"id": tc["id"], "name": tc["name"], "args": args, "result": result}
                traces.append(trace)
                yield {"event": "tool_result", "data": trace}
                messages.append({"role": "tool", "tool_call_id": tc["id"],
                                 "content": json.dumps(result, ensure_ascii=False)[:6000]})
        if not answer.strip():
            errored = True
            yield {"event": "error", "data": {"message": EMPTY_REPLY_MSG, "code": "empty_reply"}}
    except llm.LLMError as e:
        errored = True
        yield {"event": "error", "data": {"message": str(e)}}
    except Exception as e:  # 网络等异常
        errored = True
        yield {"event": "error", "data": {"message": f"{type(e).__name__}: {e}"}}
    finally:
        # ask_bot 子调用用量已由工具单独记账；这里只记本 Bot 的主调用
        db.log_usage(user_id, bot["id"], "chat", usage_total)
        stored = answer if answer.strip() else ("⚠️ " + EMPTY_REPLY_MSG if errored else "（无回复）")
        mid = db.add_message(user_id, bot["id"], "assistant", stored, traces or None)
    yield {"event": "done", "data": {"message_id": mid, "usage": usage_total}}


async def run_once(user_id: int, bot: dict, question: str, shared_context: str,
                   from_bot: dict, depth: int, chain: list | None = None, turn: TurnState | None = None
                   ) -> tuple[str, dict, str]:
    """被委派 Bot 的非流式执行：独立上下文（Context isolation）——只含 question + shared_context + 发起方公开资料，
    绝不携带任何一方的聊天历史。仅可使用目标 Bot 自身白名单内、且深度允许的工具。返回 (answer, usage, payload)。"""
    user_msg = delegation_message(from_bot, question, shared_context)
    messages = [{"role": "system", "content": system_prompt(user_id, bot, delegated_by=from_bot, depth=depth)},
                {"role": "user", "content": user_msg}]
    ctx = ToolContext(user_id=user_id, bot=bot, depth=depth, chain=list(chain or []), turn=turn or TurnState())
    tools = get_schemas(bot, depth)
    usage_total: dict = {}
    for _round in range(MAX_TOOL_ROUNDS + 1):
        use_tools = (tools or None) if _round < MAX_TOOL_ROUNDS else None
        for attempt in range(EMPTY_REPLY_RETRIES + 1):
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
            result = await run_tool(ctx, tc["function"]["name"], tc["function"].get("arguments", "{}"))
            messages.append({"role": "tool", "tool_call_id": tc["id"],
                             "content": json.dumps(result, ensure_ascii=False)[:6000]})
    return f"（{bot['name']} 暂时没有给出答复）", usage_total, user_msg
