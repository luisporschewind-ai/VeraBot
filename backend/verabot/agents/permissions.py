"""权限（Permissions）：工具白名单 + 委派深度 + 委派目标。所有判定都在服务端执行，不依赖 prompt。"""
from .. import db
from ..tools.registry import REGISTRY


def is_permitted(bot: dict, name: str, depth: int) -> tuple[bool, str]:
    """服务端权限判定：工具存在 + 在 Bot 白名单内 + 委派类工具未超过最大深度。"""
    from ..core.config import MAX_DELEGATION_DEPTH   # 调用时读取（测试可临时调整）
    t = REGISTRY.get(name)
    if t is None:
        return False, "unknown_tool"
    if name not in (bot.get("allowed_tools") or []):
        return False, "tool_not_allowed"
    if t.delegation and depth >= MAX_DELEGATION_DEPTH:
        return False, "max_depth"
    return True, ""


def get_schemas(bot: dict, depth: int) -> list[dict]:
    """只向模型暴露该 Bot 有权使用的工具（最小暴露面）；真正的拦截在 run_tool。"""
    return [t.schema() for t in REGISTRY.values() if is_permitted(bot, t.name, depth)[0]]


def delegation_targets(user_id: int, bot: dict) -> list[dict]:
    """当前 Bot 可委派的目标：在其 delegate_to 白名单中、且对方 accept_delegation。"""
    allowed = set(bot.get("delegate_to") or [])
    return [b for b in db.list_bots(user_id) if b["id"] in allowed and b["id"] != bot["id"] and b.get("accept_delegation")]
