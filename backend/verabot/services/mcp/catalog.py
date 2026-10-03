"""内置 MCP 目录。M1 只有两个免授权的公网服务，地址与开关都来自环境变量。

Microsoft Learn 默认开启；AWS Knowledge 默认关闭（有速率限制，只作备用）。
"""
from __future__ import annotations

import os

LEARN_URL = "https://learn.microsoft.com/api/mcp"
AWS_URL = "https://knowledge-mcp.global.api.aws"

# 目录里写明的只读工具。注解没说「不是只读」时按只读处理；注解明确 readOnlyHint=false 时不放宽。
READ_ONLY_TOOLS = {
    "microsoft_learn": frozenset({
        "microsoft_docs_search",
        "microsoft_code_sample_search",
        "microsoft_docs_fetch",
    }),
    "aws_knowledge": frozenset({"aws___list_regions"}),
}

_LABELS = {
    "microsoft_docs_search": "搜索微软文档",
    "microsoft_code_sample_search": "搜索代码示例",
    "microsoft_docs_fetch": "获取微软文档",
    "aws___list_regions": "列出 AWS 区域",
}


def _url(env_key: str, default: str) -> str:
    if env_key in os.environ:
        return os.environ[env_key].strip()
    return default


def _enabled(env_key: str, default: bool) -> bool:
    raw = os.getenv(env_key)
    if raw is None:
        return default
    return raw.strip().lower() not in ("0", "false", "no", "off")


def entries() -> list[dict]:
    learn_on = _enabled("VERABOT_MCP_LEARN_ENABLED", True)
    aws_on = _enabled("VERABOT_MCP_AWS_ENABLED", False)
    return [
        {
            "catalog_id": "microsoft_learn",
            "slug": "learn",
            "name": "Microsoft Learn",
            "description": "微软官方文档。免授权，Streamable HTTP（响应为 SSE，带 Mcp-Session-Id）。",
            "trust": "verified",
            "transport": "streamable_http",
            "auth": "none",
            "url": _url("VERABOT_MCP_LEARN_URL", LEARN_URL),
            "enabled": learn_on,
            "enabled_by_default": learn_on,
        },
        {
            "catalog_id": "aws_knowledge",
            "slug": "aws",
            "name": "AWS Knowledge",
            "description": "AWS 知识库。免授权，响应为 JSON；默认关闭。",
            "trust": "verified",
            "transport": "streamable_http",
            "auth": "none",
            "url": _url("VERABOT_MCP_AWS_URL", AWS_URL),
            "enabled": aws_on,
            "enabled_by_default": aws_on,
        },
    ]


def by_id(catalog_id: str) -> dict | None:
    return next((item for item in entries() if item["catalog_id"] == catalog_id), None)


def by_slug(slug: str) -> dict | None:
    return next((item for item in entries() if item["slug"] == slug), None)


def label_for(mcp_name: str, title: str | None) -> str:
    """目录里有中文名就用中文名（界面不显示英文）；否则用服务器给的 title，再退回原名。"""
    if mcp_name in _LABELS:
        return _LABELS[mcp_name]
    if title and title.strip() and title.strip() != mcp_name:
        return title.strip()
    return mcp_name
