"""v31 -> v32: Bot 开场词模板（DeepSeek 一次生成，客户端本地组装）。"""
from ._util import _add_column


def migrate(c, ver: int) -> None:
    _add_column(c, "bots", "opening_templates", "TEXT")
