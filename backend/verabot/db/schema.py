"""表结构（Models / Schema）与幂等迁移（Migration v1 → v14）的入口 / 门面。

DDL 与每个版本的迁移步骤在 db/migrations/（一个版本一个模块）；这里原样 re-export 旧名字，
`from verabot import db` / `db.init_db()` / `db.SCHEMA` 等写法不变。
"""
from .database import tx
from .migrations import SCHEMA_VERSION, apply as _apply_migrations
from .migrations._util import _add_column, _columns  # noqa: F401
from .migrations.v001_base import SCHEMA  # noqa: F401
from .migrations.v002_permissions import ALL_TOOLS_V2  # noqa: F401
from .migrations.v007_mcp import MCP_SCHEMA  # noqa: F401
from .migrations.v009_auth import AUTH_SCHEMA  # noqa: F401
from .migrations.v010_plugins import PLUGIN_SCHEMA  # noqa: F401
from .migrations.v011_reminders import (REMINDER_SCHEMA, _backfill_reminders, _backup_before_v11,  # noqa: F401
                                        _legacy_due)
from .migrations.v012_attachments import ATTACHMENT_SCHEMA  # noqa: F401

__all__ = ["SCHEMA", "SCHEMA_VERSION", "ALL_TOOLS_V2", "AUTH_SCHEMA", "MCP_SCHEMA", "PLUGIN_SCHEMA",
           "REMINDER_SCHEMA", "ATTACHMENT_SCHEMA", "init_db"]


def init_db():
    """建表 + 幂等迁移（Idempotent migration）。

    v1 → v2：多 Agent 权限模型 / 协作审计 / 用户预算。
    v2 → v3：用户昵称、用户头像、Bot 照片头像（表情符号字段保持不变）。
    v3 → v4：长期记忆 memories 表 + bots.memory_access / users.memory_enabled / messages.memory_ids。
    v4 → v5：bots.tags（JSON 数组，默认 []）。不改权限、记忆、头像。
    v5 → v6：bots.pinned_at（UTC ISO 8601，NULL = 未置顶）。
    v6 → v7：MCP 表（mcp_servers / mcp_tools 等）。不改 allowed_tools，不给存量 Bot 授予 MCP 工具。
    v7 → v8：MCP 同意时间、同步状态、熔断计数。不改工具定义、白名单或已有服务器行的身份字段。
    v8 → v9：账号邮箱 / 手机号（部分唯一索引）、邮箱验证时间、token_version、登录失败锁定；
             新表 auth_codes（邮箱验证码，只存哈希）、auth_refresh_tokens（刷新令牌，只存哈希）。
             不改用户名、密码哈希和任何业务数据；demo 等老账号继续用用户名登录。
    v9 → v10：user_plugins（安装关系）+ mcp_servers.plugin_id。不预装。
             用过（已同意、已同步，或任一 Bot 白名单含该服务工具）的目录服务记为 installed；
             没用过的不写 uninstalled 墓碑。不改 consent_at、工具缓存和 allowed_tools。
             演示账号的 Learn 若已同意，会作为「用过」保留为已安装。
    v10 → v11：提醒补列（状态、时区、重复、归属）并回填；新建 reminder_events、notifications、
             notification_deliveries、notification_prefs、push_devices、idempotency_keys。
             不改其他表的数据。迁移前备份 verabot.db.bak-before-v11-<时间戳>。
    v11 → v12：attachments 表（图片元数据；文件在 DATA_DIR/attachments）。v11 是提醒 R1。
    v12 → v13：需授权 MCP 连接器：mcp_credentials 加 kind / token_hint / last_verified_at，mcp_servers 加 auth_error，
             新表 mcp_oauth_clients（P2 用）。只加列 / 建表，不改已有行。
    v13 → v14：记忆 M2。新表 memory_jobs（滚动摘要任务）、message_feedback（👍 / 👎）。只建表，不写记忆。
    """
    # v15: optional bots.appearance; historical avatars are unchanged.
    _backup_before_v11()
    with tx() as c:
        _apply_migrations(c)
