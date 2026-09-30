"""护栏（Guardrails）：委派前的服务端检查，均不依赖 prompt。

检查顺序（与 v0.1 相同）：self → loop → not_in_allowlist → target_refuses → turn_cap → budget。
最大深度（max_depth）在工具暴露 / 执行层拦截，见 permissions.is_permitted。
"""
from dataclasses import dataclass, field

from .. import db
from ..core.config import MAX_DELEGATIONS_PER_TURN
from ..tools.registry import ToolContext


@dataclass
class Rejection:
    reason: str
    message: str
    extra: dict = field(default_factory=dict)


def allowed_target_names(ctx: ToolContext) -> list[str]:
    allowed_ids = set(ctx.bot.get("delegate_to") or [])
    return [b["name"] for b in db.list_bots(ctx.user_id) if b["id"] in allowed_ids]


def check_delegation(ctx: ToolContext, target: dict) -> Rejection | None:
    """返回 None 表示允许委派；否则返回拒绝原因（写入 delegations / audit_log）。"""
    allowed_ids = set(ctx.bot.get("delegate_to") or [])
    if target["id"] == ctx.bot["id"]:
        return Rejection("self", "不能咨询自己")
    if target["id"] in ctx.chain:
        return Rejection("loop", "检测到委派环路，已阻止")
    if target["id"] not in allowed_ids:
        return Rejection("not_in_allowlist", f"没有委派给「{target['name']}」的权限",
                         {"available_bots": allowed_target_names(ctx)})
    if not target.get("accept_delegation"):
        return Rejection("target_refuses", f"「{target['name']}」不接受其他 Bot 的委派")
    if ctx.turn.delegations >= MAX_DELEGATIONS_PER_TURN:
        return Rejection("turn_cap", f"本轮对话的委派次数已达上限（{MAX_DELEGATIONS_PER_TURN} 次）")
    used, budget = db.token_budget(ctx.user_id)
    if used >= budget:
        return Rejection("budget", "今日 Token 额度已用完，无法继续委派")
    return None
