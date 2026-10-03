"""MCP 结果视为不可信数据：清洗、截断、用标记包起来。"""
from __future__ import annotations

import os
import re

from ...core.config import MCP_MAX_RESULT_CHARS_DEFAULT

_INVISIBLE = re.compile(
    "[\u200b\u200c\u200d\u200e\u200f\u2060\u2066-\u2069\ufeff\u202a-\u202e]"
)
_COMMENT = re.compile(r"<!--[\s\S]*?-->")
_SCRIPT = re.compile(r"<(script|style)[^>]*>[\s\S]*?</\1>", re.IGNORECASE)
_TAG = re.compile(r"<[^>\n]{0,200}>")


def max_chars() -> int:
    raw = os.getenv("VERABOT_MCP_MAX_RESULT_CHARS", str(MCP_MAX_RESULT_CHARS_DEFAULT))
    try:
        return max(1, int(raw))
    except ValueError:
        return MCP_MAX_RESULT_CHARS_DEFAULT


def clean_text(text: str) -> str:
    text = _SCRIPT.sub("", text or "")
    text = _COMMENT.sub("", text)
    text = _TAG.sub("", text)
    text = _INVISIBLE.sub("", text)
    return text


def escape_markers(text: str) -> str:
    text = text.replace("</untrusted_tool_result>", "&lt;/untrusted_tool_result&gt;")
    text = text.replace("<untrusted_tool_result", "&lt;untrusted_tool_result")
    return text


def wrap(server: str, tool: str, call_id: str, text: str) -> tuple[str, bool]:
    body = escape_markers(clean_text(text))
    limit = max_chars()
    truncated = len(body) > limit
    if truncated:
        body = body[:limit] + "\n[truncated]"
    wrapped = (
        f'<untrusted_tool_result server="{server}" tool="{tool}" call_id="{call_id}">\n'
        f"{body}\n</untrusted_tool_result>"
    )
    return wrapped, truncated


def clean_description(server_name: str, description: str) -> str:
    body = clean_text(description or "")
    prefix = f"[来自 MCP 服务 {server_name}] "
    text = prefix + body
    return text[:1024]
