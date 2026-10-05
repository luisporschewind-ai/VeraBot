"""风格校准（M2）：用户原话里的规则命中，以及 👎 原因聚合。只生成待确认提议，不自动生效。"""
from __future__ import annotations

from ...core import config
from . import policy

# 短语 → 提议正文。较长的写在前面，避免短词先截走。
RULES: tuple[tuple[str, str], ...] = (
    ("再短一点", config.MEMORY_STYLE_SHORTER),
    ("简洁点", config.MEMORY_STYLE_SHORTER),
    ("说重点", config.MEMORY_STYLE_SHORTER),
    ("详细一点", "回答再详细一点"),
    ("别用列表", "回答不要用列表"),
    ("用英文", "用英文回答"),
)

REASON_STYLE = {
    "too_long": config.MEMORY_STYLE_SHORTER,
}


def match_style(text: str) -> str | None:
    """用户消息命中风格短语时返回提议正文，否则 None。不调用模型。"""
    t = policy.clean(text)
    if not t:
        return None
    for phrase, content in RULES:
        if phrase in t:
            return content
    return None


def trace_for(proposal: dict) -> dict:
    """合成一条 remember 工具结果，让既有确认卡片能渲染。id 不含正文。"""
    mid = proposal.get("memory_id")
    return {
        "id": f"style-{mid}",
        "name": "remember",
        "args": {"content": proposal.get("content") or "", "type": "style", "scope": "bot"},
        "result": proposal,
    }
