"""v39 → v40：Bot 能力默认全开（2026-10-22 产品决定，逆转原来的最小权限默认值）。

新建 Bot 的默认值由 `services/bots.py::create_perms` 提供；本迁移只负责把**存量** Bot 一并打开：

- `allowed_tools` = 全部内置工具 + 该账号已连接且已同意服务的 active MCP 工具（每 Bot 最多 20 个，
  按工具全名排序截断；之后新同步 / 新安装的工具仍不自动授权，防 rug-pull 规则不变）。
- `accept_delegation` = 1（接受其他 Bot 委派）。
- `delegate_to` = 该账号内其他全部 Bot（互通；实际委派仍受对方接受委派、深度、预算等护栏约束）。
- `memory_access` = `bot_and_global`（沿用新建 Bot 的默认记忆授权）。

迁移前备份 `verabot.db.bak-before-v40-<时间戳>`。回填只写权限列，不删消息、记忆或任何业务数据；
幂等（只在库版本 < 40 时执行一次）。
"""
import json
import sqlite3
from datetime import datetime
from pathlib import Path

MCP_MAX_TOOLS_PER_BOT = 20

# 迁移必须固定当时的工具集合，不能随以后的注册表变化（否则重跑旧库会得到不同的白名单）。
BUILTIN_TOOLS_V40 = (
    "ask_bot",
    "create_reminder",
    "get_weather",
    "list_reminders",
    "manage_reminder",
    "propose_task",
    "web_read_result",
    "web_search",
)


def backup_before_v40() -> None:
    from ..database import DB_PATH
    path = Path(DB_PATH)
    if not path.is_file():
        return
    source = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    try:
        try:
            version = source.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()
        except sqlite3.OperationalError:
            return
        if not version or int(version[0]) >= 40:
            return
        destination = path.with_name(
            path.name + ".bak-before-v40-" + datetime.now().strftime("%Y%m%d-%H%M%S-%f")
        )
        target = sqlite3.connect(destination)
        try:
            source.backup(target)
        finally:
            target.close()
        destination.chmod(0o600)
    finally:
        source.close()


def _mcp_tools(c, user_id: int) -> list[str]:
    rows = c.execute(
        """SELECT t.full_name FROM mcp_tools t
           JOIN mcp_servers s ON s.id = t.server_id AND s.user_id = t.user_id
           WHERE t.user_id=? AND t.status='active'
             AND s.status='connected' AND s.consent_at IS NOT NULL
           ORDER BY t.full_name""",
        (user_id,),
    ).fetchall()
    return sorted({r[0] for r in rows})[:MCP_MAX_TOOLS_PER_BOT]


def migrate(c, ver: int) -> None:
    if ver >= 40:
        return
    user_ids = [r[0] for r in c.execute("SELECT id FROM users ORDER BY id").fetchall()]
    for user_id in user_ids:
        tools = sorted({*BUILTIN_TOOLS_V40, *_mcp_tools(c, user_id)})
        bot_ids = [r[0] for r in c.execute(
            "SELECT id FROM bots WHERE user_id=? ORDER BY id", (user_id,)).fetchall()]
        for bot_id in bot_ids:
            delegates = [x for x in bot_ids if x != bot_id]
            c.execute(
                """UPDATE bots SET allowed_tools=?, delegate_to=?, accept_delegation=1,
                          memory_access='bot_and_global'
                   WHERE id=? AND user_id=?""",
                (json.dumps(tools), json.dumps(delegates), bot_id, user_id),
            )
