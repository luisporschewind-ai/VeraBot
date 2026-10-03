"""每次启动：把超出当前上限的存量 bots.tags 收敛（结构不变，仍是 v5）。原本就排在 v11 之后、v12 之前。"""
import json


def migrate(c, ver: int) -> None:
    # 标签上限收紧 (2026-10-01：最多 3 个、每个 4 字)。结构不变 (仍是 v5)；每次启动把超限的存量标签收敛：
    # 保留前 3 个、每个截断到 4 字、去重。幂等，只改写确实变化的行。
    from ...core.tags import coerce_stored_tags
    for bid, raw in c.execute("SELECT id, tags FROM bots WHERE tags != '[]'").fetchall():
        try:
            old = json.loads(raw or "[]")
        except ValueError:
            old = None
        new = coerce_stored_tags(old)
        if new != old:
            c.execute("UPDATE bots SET tags=? WHERE id=?", (json.dumps(new, ensure_ascii=False), bid))
