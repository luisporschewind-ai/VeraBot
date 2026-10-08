"""v14 -> v15: optional versioned appearance; existing avatars stay untouched."""
from ._util import _add_column


def migrate(c, ver: int) -> None:
    _add_column(c, "bots", "appearance", "TEXT")
