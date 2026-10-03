"""幂等迁移（Migration v1 → v12），一个版本一个模块，按原 init_db() 的语句顺序依次执行。

入口仍是 `db.schema.init_db()`（= `db.init_db()`）：先 `v011_reminders._backup_before_v11()`，
再在同一个事务里调用 `apply(c)`。每一步都幂等（IF NOT EXISTS / 先查列再 ALTER），
只在「从旧版本升上来」时才做的回填由 `ver < N` 守住。

顺序与 v12 之前完全一致：v001 基础表 → v002 … v011 → tags_coerce（每次启动，原本就在 v11 之后）
→ v012 附件 → 写 schema_meta.version。不要调换：后面的步骤依赖前面补的列（如 v010 回填读 consent_at）。
"""
from . import (tags_coerce, v001_base, v002_permissions, v003_profile, v004_memory, v005_tags, v006_pinned,
               v007_mcp, v008_mcp_sync, v009_auth, v010_plugins, v011_reminders, v012_attachments)

SCHEMA_VERSION = 12  # v11 = 提醒 R1，v12 = 图片附件

STEPS = (
    v002_permissions, v003_profile, v004_memory, v005_tags, v006_pinned, v007_mcp, v008_mcp_sync,
    v009_auth, v010_plugins, v011_reminders, tags_coerce, v012_attachments,
)


def apply(c) -> None:
    """在调用方的事务连接上执行全部迁移步骤。"""
    ver = v001_base.migrate(c)
    for step in STEPS:
        step.migrate(c, ver)
    if ver < SCHEMA_VERSION:
        c.execute("INSERT OR REPLACE INTO schema_meta(key,value) VALUES ('version', ?)", (str(SCHEMA_VERSION),))
