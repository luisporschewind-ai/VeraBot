"""v1 → v2：多 Agent 权限模型 / 协作审计 / 用户预算。"""
import json

from ._util import _add_column

ALL_TOOLS_V2 = ["get_weather", "create_reminder", "list_reminders", "ask_bot"]


def migrate(c, ver: int) -> None:
    # --- bots：权限字段。列默认值 = 最小权限（Least privilege） ---
    _add_column(c, "bots", "allowed_tools", "TEXT NOT NULL DEFAULT '[]'")        # 工具白名单 Tool allowlist
    _add_column(c, "bots", "delegate_to", "TEXT NOT NULL DEFAULT '[]'")          # 可委派目标 Bot id 白名单
    _add_column(c, "bots", "accept_delegation", "INTEGER NOT NULL DEFAULT 0")    # 是否接受其他 Bot 委派
    # --- users：个人 Token 预算覆盖（NULL = 使用全局 DAILY_TOKEN_QUOTA） ---
    _add_column(c, "users", "token_budget", "INTEGER")
    # --- delegations：完整协作审计字段 ---
    for name, ddl in [("status", "TEXT NOT NULL DEFAULT 'ok'"), ("reason", "TEXT"), ("depth", "INTEGER NOT NULL DEFAULT 1"),
                      ("payload", "TEXT"), ("shared_truncated", "INTEGER NOT NULL DEFAULT 0"),
                      ("prompt_tokens", "INTEGER NOT NULL DEFAULT 0"), ("completion_tokens", "INTEGER NOT NULL DEFAULT 0"),
                      ("total_tokens", "INTEGER NOT NULL DEFAULT 0")]:
        _add_column(c, "delegations", name, ddl)
    c.execute("""CREATE TABLE IF NOT EXISTS audit_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            bot_id INTEGER, kind TEXT NOT NULL, detail TEXT, created_at TEXT NOT NULL)""")
    c.execute("CREATE INDEX IF NOT EXISTS idx_deleg_user ON delegations(user_id, id)")
    if ver < 2:
        # 存量 Bot（v0.1 中本就拥有全部工具、可互相委派）：授予等价权限，保证 demo 行为不变
        for (uid,) in c.execute("SELECT DISTINCT user_id FROM bots").fetchall():
            ids = [r[0] for r in c.execute("SELECT id FROM bots WHERE user_id=? ORDER BY id", (uid,)).fetchall()]
            for bid in ids:
                c.execute("UPDATE bots SET allowed_tools=?, delegate_to=?, accept_delegation=1 WHERE id=?",
                          (json.dumps(ALL_TOOLS_V2), json.dumps([x for x in ids if x != bid]), bid))
        # 历史委派记录：孤儿清理（被删除 Bot 的记录）
        c.execute("DELETE FROM delegations WHERE from_bot_id NOT IN (SELECT id FROM bots) "
                  "OR to_bot_id NOT IN (SELECT id FROM bots)")
