"""内置插件目录。免授权 MCP 插件（Learn、AWS）、需令牌的只读连接器（GitHub、Linear），以及天气 / 提醒两个内置插件。

不从网络拉取。`default_installed` 不在这里：见 `core.config.plugin_default_installed`（当前为空）。
"""
from __future__ import annotations

DATA_NOTICE = "工具返回的内容会发送给 DeepSeek 用来生成回答。"
TOKEN_NOTICE = "令牌加密保存在 VeraBot 服务器，不会发给 DeepSeek，也不会返回给 App。"
BUILTIN_NOTICE = "内置能力由 VeraBot 提供，不需要单独同意。"


def mcp_plugins() -> list[dict]:
    return [
        {
            "plugin_id": "microsoft_learn",
            "kind": "mcp",
            "name": "Microsoft Learn",
            "description": "查询微软官方技术文档与代码示例。",
            "category": "知识与文档",
            "publisher": "Microsoft",
            "version": "1.0.0",
            "icon": "book.closed",
            "auth_mode": "none",
            "trust": "verified",
            "data_notice": DATA_NOTICE,
            "catalog_id": "microsoft_learn",
            "removable": True,
            "consent_required": True,
            "tools": [],
        },
        {
            "plugin_id": "aws_knowledge",
            "kind": "mcp",
            "name": "AWS Knowledge",
            "description": "查询 AWS 官方文档与区域等信息。",
            "category": "知识与文档",
            "publisher": "Amazon Web Services",
            "version": "1.0.0",
            "icon": "cloud",
            "auth_mode": "none",
            "trust": "verified",
            "data_notice": DATA_NOTICE,
            "catalog_id": "aws_knowledge",
            "removable": True,
            "consent_required": True,
            "tools": [],
        },
        {
            "plugin_id": "github",
            "kind": "mcp",
            "name": "GitHub",
            "description": "只读访问你授权的 GitHub 仓库：文件、提交、issue、PR。",
            "category": "开发工具",
            "publisher": "GitHub",
            "version": "1.0.0",
            "icon": "chevron.left.forwardslash.chevron.right",
            "auth_mode": "bearer",
            "trust": "verified",
            "data_notice": "仓库内容会发送给 DeepSeek 用来生成回答。" + TOKEN_NOTICE,
            "catalog_id": "github",
            "removable": True,
            "consent_required": True,
            "tools": [],
        },
        {
            "plugin_id": "linear",
            "kind": "mcp",
            "name": "Linear",
            "description": "只读访问 Linear 的 issue 与项目。",
            "category": "开发工具",
            "publisher": "Linear",
            "version": "1.0.0",
            "icon": "list.bullet.rectangle",
            "auth_mode": "bearer",
            "trust": "verified",
            "data_notice": "Linear 内容会发送给 DeepSeek 用来生成回答。" + TOKEN_NOTICE,
            "catalog_id": "linear",
            "removable": True,
            "consent_required": True,
            "tools": [],
        },
    ]


def builtins() -> list[dict]:
    return [
        {
            "plugin_id": "builtin_weather",
            "kind": "builtin",
            "name": "天气",
            "description": "查询天气。数据来自 Open-Meteo。",
            "category": "",
            "publisher": "VeraBot",
            "version": "1.0.0",
            "icon": "cloud.sun",
            "auth_mode": "none",
            "trust": "verified",
            "data_notice": BUILTIN_NOTICE,
            "catalog_id": None,
            "removable": False,
            "consent_required": False,
            "tools": ["get_weather"],
        },
        {
            "plugin_id": "builtin_reminder",
            "kind": "builtin",
            "name": "提醒",
            "description": "创建提醒，查看还没完成的提醒，完成、稍后或修改自己的提醒。",
            "category": "",
            "publisher": "VeraBot",
            "version": "1.0.0",
            "icon": "bell",
            "auth_mode": "none",
            "trust": "verified",
            "data_notice": BUILTIN_NOTICE,
            "catalog_id": None,
            "removable": False,
            "consent_required": False,
            "tools": ["create_reminder", "list_reminders", "manage_reminder"],
        },
    ]


def entries() -> list[dict]:
    return builtins() + mcp_plugins()


def by_id(plugin_id: str) -> dict | None:
    return next((item for item in entries() if item["plugin_id"] == plugin_id), None)
