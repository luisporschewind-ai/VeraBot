"""内置 MCP 目录。地址与开关都来自环境变量。

免授权：Learn、AWS。需授权（MCP_AUTH_CONNECTORS_PLAN v1.0 P1，静态令牌 static_bearer）：GitHub、Linear，均只读。
目录字段：auth（none / bearer / oauth）、static_headers（固定请求头）、credential（令牌头与格式）、
tool_allowlist（只接收名单内工具；None = 不限）、timeout（单服务超时秒数）、account_probe（取账号名 / 到期时间）。

Microsoft Learn 默认开启；AWS Knowledge 默认关闭（有速率限制，只作备用）。
"""
from __future__ import annotations

import os

LEARN_URL = "https://learn.microsoft.com/api/mcp"
AWS_URL = "https://knowledge-mcp.global.api.aws"
GITHUB_URL = "https://api.githubcopilot.com/mcp/readonly"
GITHUB_API_URL = "https://api.github.com"
LINEAR_URL = "https://mcp.linear.app/mcp/readonly"

# GitHub P1 只读工具（计划 §7.1，15 个）。名单之外的工具同步时拒绝并审计。
GITHUB_TOOLS = frozenset({
    "get_file_contents", "list_branches", "list_commits", "get_commit", "list_tags", "list_releases",
    "get_latest_release", "search_code", "search_repositories", "issue_read", "list_issues", "search_issues",
    "pull_request_read", "list_pull_requests", "search_pull_requests",
})

# 目录里写明的只读工具。注解没说「不是只读」时按只读处理；注解明确 readOnlyHint=false 时不放宽。
READ_ONLY_TOOLS = {
    "microsoft_learn": frozenset({
        "microsoft_docs_search",
        "microsoft_code_sample_search",
        "microsoft_docs_fetch",
    }),
    "aws_knowledge": frozenset({"aws___list_regions"}),
    "github": GITHUB_TOOLS,
}

_LABELS = {
    "microsoft_docs_search": "搜索微软文档",
    "microsoft_code_sample_search": "搜索代码示例",
    "microsoft_docs_fetch": "获取微软文档",
    "aws___list_regions": "列出 AWS 区域",
    "get_file_contents": "读取文件",
    "list_branches": "列出分支",
    "list_commits": "列出提交",
    "get_commit": "查看提交",
    "list_tags": "列出标签",
    "list_releases": "列出发布",
    "get_latest_release": "查看最新发布",
    "search_code": "搜索代码",
    "search_repositories": "搜索仓库",
    "issue_read": "读取 issue",
    "list_issues": "列出 issue",
    "search_issues": "搜索 issue",
    "pull_request_read": "读取 PR",
    "list_pull_requests": "列出 PR",
    "search_pull_requests": "搜索 PR",
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
        {
            "catalog_id": "github",
            "slug": "github",
            "name": "GitHub",
            "description": "GitHub 官方远程 MCP（只读）。需要 Fine-grained PAT。",
            "trust": "verified",
            "transport": "streamable_http",
            "auth": "bearer",
            "url": _url("VERABOT_MCP_GITHUB_URL", GITHUB_URL),
            "enabled": True,
            "enabled_by_default": False,
            "static_headers": {
                "X-MCP-Readonly": "true",
                "X-MCP-Toolsets": "repos,issues,pull_requests",
                "X-MCP-Lockdown": "true",
            },
            "credential": {
                "header": "Authorization", "scheme": "Bearer",
                "pattern": r"^(github_pat_[A-Za-z0-9_]{20,}|ghp_[A-Za-z0-9]{20,})$",
                "discouraged_prefix": "ghp_",
                "help_url": "https://github.com/settings/personal-access-tokens/new",
                "help": "在 GitHub 创建 Fine-grained 令牌：只选测试仓库；Contents、Issues、Pull requests 设为只读；"
                        "有效期 30 天。不要使用对所有仓库生效的 classic 令牌。",
            },
            "tool_allowlist": GITHUB_TOOLS,
            "timeout": 30.0,
            "account_probe": {
                "url": _url("VERABOT_GITHUB_API_URL", GITHUB_API_URL).rstrip("/") + "/user",
                "field": "login",
                "expiry_header": "github-authentication-token-expiration",
            },
        },
        {
            "catalog_id": "linear",
            "slug": "linear",
            "name": "Linear",
            "description": "Linear 官方远程 MCP（只读）。需要 Linear API Key。",
            "trust": "verified",
            "transport": "streamable_http",
            "auth": "bearer",
            "url": _url("VERABOT_MCP_LINEAR_URL", LINEAR_URL),
            "enabled": True,
            "enabled_by_default": False,
            "static_headers": {},
            "credential": {
                "header": "Authorization", "scheme": "Bearer",
                "pattern": r"^lin_api_[A-Za-z0-9]{20,}$",
                "help_url": "https://linear.app/settings/account/security",
                "help": "在 Linear「Settings › Security & access › Personal API keys」创建 API Key，只用于只读。",
            },
            # 工具名待首次带令牌的 tools/list 确认（CONN-LIVE-06）；在那之前不限名单，风险按注解判断，非只读仍需确认。
            "tool_allowlist": None,
            "timeout": 30.0,
            "account_probe": None,
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
