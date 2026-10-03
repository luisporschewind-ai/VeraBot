"""v4 → v5：bots.tags（JSON 数组，默认 []）。存量标签的收敛见 tags_coerce.py（每次启动执行）。"""
from ._util import _add_column


def migrate(c, ver: int) -> None:
    # --- v5：Bot 标签。JSON 字符串数组，默认 []。不回填、不改写已有权限 / 记忆 / 头像 ---
    _add_column(c, "bots", "tags", "TEXT NOT NULL DEFAULT '[]'")
