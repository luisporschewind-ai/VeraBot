"""v5 → v6：bots.pinned_at（UTC ISO 8601，NULL = 未置顶）。"""
from ._util import _add_column


def migrate(c, ver: int) -> None:
    # --- v6：Bot 置顶。NULL 表示未置顶，不回填其他数据 ---
    _add_column(c, "bots", "pinned_at", "TEXT")
