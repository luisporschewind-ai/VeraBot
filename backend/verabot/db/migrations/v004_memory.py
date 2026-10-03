"""v3 → v4：长期记忆（memories 表在基础 DDL 里）+ bots.memory_access / users.memory_enabled / messages.memory_ids。"""
from ._util import _add_column


def migrate(c, ver: int) -> None:
    # --- v4：记忆（Memory）。Boss 决策（2026-10-01）：默认开启——新 Bot 与存量 Bot 都是 bot_and_global，
    #     用户总开关默认开。迁移不写入任何记忆，不改动 allowed_tools / delegate_to ---
    _add_column(c, "bots", "memory_access", "TEXT NOT NULL DEFAULT 'bot_and_global'")  # none / bot / bot_and_global
    _add_column(c, "users", "memory_enabled", "INTEGER NOT NULL DEFAULT 1")             # 用户总开关
    _add_column(c, "messages", "memory_ids", "TEXT")                                    # 本条回复注入了哪些记忆（JSON list）
