"""DeepSeek（OpenAI 兼容）客户端。服务端统一持有 Key，用户无需填写。"""
import json
from typing import AsyncIterator

import httpx

from ..core.config import DEEPSEEK_API_KEY, DEEPSEEK_BASE_URL, DEEPSEEK_MODEL, DEEPSEEK_THINKING


class LLMError(RuntimeError):
    pass


def _headers():
    if not DEEPSEEK_API_KEY:
        raise LLMError("服务器未配置 DEEPSEEK_API_KEY")
    return {"Authorization": f"Bearer {DEEPSEEK_API_KEY}", "Content-Type": "application/json"}


def _body(messages, tools, stream):
    body = {"model": DEEPSEEK_MODEL, "messages": messages, "stream": stream, "temperature": 0.7}
    if not DEEPSEEK_THINKING:
        # 关闭思考模式：否则带 tools 的多轮请求缺 reasoning_content 会 400（见 core/config.py）
        body["thinking"] = {"type": "disabled"}
    if tools:
        body["tools"] = tools
    if stream:
        body["stream_options"] = {"include_usage": True}
    return body


async def stream_chat(messages: list, tools: list | None) -> AsyncIterator[tuple[str, object]]:
    """产出事件：("delta", str) / ("tool_calls", list) / ("usage", dict) / ("finish", reason)"""
    calls: dict[int, dict] = {}
    finish = None
    async with httpx.AsyncClient(timeout=httpx.Timeout(120, connect=15)) as client:
        async with client.stream("POST", f"{DEEPSEEK_BASE_URL}/chat/completions",
                                 headers=_headers(), json=_body(messages, tools, True)) as r:
            if r.status_code != 200:
                text = (await r.aread()).decode(errors="ignore")[:300]
                raise LLMError(f"DeepSeek HTTP {r.status_code}: {text}")
            async for line in r.aiter_lines():
                if not line.startswith("data:"):
                    continue
                data = line[5:].strip()
                if data == "[DONE]":
                    break
                chunk = json.loads(data)
                if chunk.get("usage"):
                    yield "usage", chunk["usage"]
                for ch in chunk.get("choices") or []:
                    delta = ch.get("delta") or {}
                    if delta.get("content"):
                        yield "delta", delta["content"]
                    for tc in delta.get("tool_calls") or []:
                        slot = calls.setdefault(tc.get("index", 0), {"id": "", "name": "", "arguments": ""})
                        slot["id"] = tc.get("id") or slot["id"]
                        fn = tc.get("function") or {}
                        slot["name"] += fn.get("name") or ""
                        slot["arguments"] += fn.get("arguments") or ""
                    if ch.get("finish_reason"):
                        finish = ch["finish_reason"]
    if calls:
        yield "tool_calls", [calls[i] for i in sorted(calls)]
    yield "finish", finish


async def complete(messages: list, tools: list | None) -> tuple[dict, dict]:
    """非流式调用，返回 (message, usage)。用于被委派的 Bot。"""
    async with httpx.AsyncClient(timeout=httpx.Timeout(120, connect=15)) as client:
        r = await client.post(f"{DEEPSEEK_BASE_URL}/chat/completions", headers=_headers(),
                              json=_body(messages, tools, False))
    if r.status_code != 200:
        raise LLMError(f"DeepSeek HTTP {r.status_code}: {r.text[:300]}")
    d = r.json()
    choice = d["choices"][0]
    msg = dict(choice["message"])
    msg["_finish_reason"] = choice.get("finish_reason")  # 供日志 / 空回复诊断（BUG-09）
    return msg, d.get("usage") or {}
