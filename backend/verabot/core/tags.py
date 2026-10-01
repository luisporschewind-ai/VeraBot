"""Bot 标签（tags）规则：上限与「存量数据宽松收敛」。纯函数，供 api/schemas（严格校验）与 db（读取 / 启动时收敛）共用。

2026-10-01 重新设计：每个 Bot 最多 3 个标签，每个最多 4 个字（按 Unicode 码点计，与 iOS `BotTagRules` 一致）。
"""
import unicodedata

MAX_BOT_TAGS = 3
MAX_TAG_CHARS = 4


def coerce_stored_tags(raw) -> list[str]:
    """把库里已有的标签收敛到当前上限，永不抛错（用于读取与启动时的数据修正）：
    trim → 去掉控制字符 → 丢掉空白 → 每个截断到前 4 个字 → 去重（保留首次出现的顺序）→ 只保留前 3 个。
    非列表 / 非文字元素一律丢弃。"""
    if not isinstance(raw, list):
        return []
    out: list[str] = []
    for item in raw:
        if not isinstance(item, str):
            continue
        tag = "".join(ch for ch in item if unicodedata.category(ch) != "Cc").strip()[:MAX_TAG_CHARS].strip()
        if tag and tag not in out:
            out.append(tag)
        if len(out) == MAX_BOT_TAGS:
            break
    return out
