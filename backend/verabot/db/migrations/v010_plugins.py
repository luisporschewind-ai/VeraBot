"""v9 → v10：user_plugins（安装关系）+ mcp_servers.plugin_id。不预装，不为未使用的目录行写墓碑。"""
from ..database import now_iso
from ._util import _add_column

# v10：插件安装关系。启用、同意、同步、熔断仍在 mcp_servers。
# 不预装任何插件。迁移只把「用过」的目录服务记为 installed，不为没用过的行写 uninstalled 墓碑。
PLUGIN_SCHEMA = """
CREATE TABLE IF NOT EXISTS user_plugins (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  plugin_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'installed',
  catalog_version TEXT,
  settings TEXT,
  installed_at TEXT, uninstalled_at TEXT,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
  UNIQUE(user_id, plugin_id)
);
CREATE INDEX IF NOT EXISTS idx_user_plugins_user ON user_plugins(user_id, status);
"""


def migrate(c, ver: int) -> None:
    # --- v10：插件。只加安装表和关联列；不预装，不为未使用的目录行写墓碑 ---
    _add_column(c, "mcp_servers", "plugin_id", "TEXT")
    c.executescript(PLUGIN_SCHEMA)
    if ver < 10:
        now = now_iso()
        c.execute(
            """UPDATE mcp_servers SET plugin_id = catalog_id
                   WHERE plugin_id IS NULL AND source='catalog'
                     AND catalog_id IS NOT NULL"""
        )
        # 用过 = 同意过、同步过，或某个 Bot 的白名单里已经有 mcp__{slug}__。
        # 目录自动补出来、但用户没碰过的行（包括默认开启却从未同意的 Learn）保持未安装，
        # 且不插入 status='uninstalled'。墓碑只留给用户以后主动卸载，避免挡住预装。
        c.execute(
            """INSERT OR IGNORE INTO user_plugins(
                       user_id, plugin_id, status, installed_at, created_at, updated_at)
                   SELECT s.user_id, s.plugin_id, 'installed', s.created_at, s.created_at, ?
                   FROM mcp_servers s
                   WHERE s.plugin_id IS NOT NULL AND (
                     s.consent_at IS NOT NULL
                     OR s.last_synced_at IS NOT NULL
                     OR EXISTS (
                       SELECT 1 FROM bots b
                       WHERE b.user_id = s.user_id
                         AND instr(b.allowed_tools, 'mcp__' || s.slug || '__') > 0
                     )
                   )""",
            (now,),
        )
