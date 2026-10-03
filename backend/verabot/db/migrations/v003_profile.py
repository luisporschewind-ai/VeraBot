"""v2 → v3：用户昵称、用户头像、Bot 照片头像（表情符号字段保持不变；avatars 表在基础 DDL 里）。"""
from ._util import _add_column


def migrate(c, ver: int) -> None:
    # --- v3：昵称与照片头像。NULL = 未设置（昵称回退用户名；头像回退首字母 / 表情） ---
    _add_column(c, "users", "nickname", "TEXT")
    _add_column(c, "users", "avatar_updated_at", "TEXT")
    _add_column(c, "bots", "image_updated_at", "TEXT")
