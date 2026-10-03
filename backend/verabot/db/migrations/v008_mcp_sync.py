"""v7 → v8：MCP 同意时间、同步状态、熔断计数。不改工具定义、白名单或已有服务器行的身份字段。"""
from ._util import _add_column


def migrate(c, ver: int) -> None:
    # --- v8：同意 / 异步同步 / 熔断。已有 v7 表用 ALTER 补列（CREATE IF NOT EXISTS 不会改旧表） ---
    _add_column(c, "mcp_servers", "consent_at", "TEXT")
    _add_column(c, "mcp_servers", "sync_status", "TEXT NOT NULL DEFAULT 'pending'")
    _add_column(c, "mcp_servers", "circuit_failures", "INTEGER NOT NULL DEFAULT 0")
    _add_column(c, "mcp_servers", "circuit_open_until", "TEXT")
    if ver < 8:
        # 已经同步成功的行标成 ok，避免升级后再次被当成「还没同步」而去连外网。
        # 同意时间留空：M1 没有记录，必须由用户重新同意后才能调用工具。
        c.execute(
            """UPDATE mcp_servers SET sync_status='ok'
                   WHERE sync_status='pending' AND status='connected' AND last_synced_at IS NOT NULL"""
        )
        c.execute(
            """UPDATE mcp_servers SET sync_status='error'
                   WHERE sync_status='pending' AND status='error'"""
        )
