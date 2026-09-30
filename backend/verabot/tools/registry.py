"""Tool Registry：新增工具只需 @tool 装饰一个 async 函数并在 __init__ 中导入。

权限执行点（Enforcement point）：所有工具调用都经过 run_tool，
在服务端校验「当前 Bot 的工具白名单 + 委派深度」（规则见 agents/permissions.py），不依赖 prompt。
越权调用被拒绝并写入 audit_log。
"""
import json
import logging
from dataclasses import dataclass, field
from typing import Any, Awaitable, Callable

log = logging.getLogger("verabot.tools")


@dataclass
class TurnState:
    """一次用户请求（一轮对话 turn）内、跨整棵委派树共享的计数器。"""
    delegations: int = 0


@dataclass
class ToolContext:
    user_id: int
    bot: dict                      # 当前执行工具的 Bot（含 allowed_tools / delegate_to / accept_delegation）
    depth: int = 0                 # 多 Agent 调用深度：0 = 用户直接对话的 Bot
    chain: list = field(default_factory=list)      # 委派链上的 Bot id（用于环路检测 Loop detection）
    turn: TurnState = field(default_factory=TurnState)
    usage: list = field(default_factory=list)      # 子调用产生的 token 用量


@dataclass
class Tool:
    name: str
    description: str
    parameters: dict
    handler: Callable[..., Awaitable[Any]]
    delegation: bool = False       # 是否为委派类工具（受 MAX_DELEGATION_DEPTH 约束）

    def schema(self) -> dict:
        return {"type": "function",
                "function": {"name": self.name, "description": self.description, "parameters": self.parameters}}


REGISTRY: dict[str, Tool] = {}


def tool(name: str, description: str, parameters: dict, delegation: bool = False):
    def deco(fn):
        REGISTRY[name] = Tool(name, description, parameters, fn, delegation)
        return fn
    return deco


async def run_tool(ctx: ToolContext, name: str, raw_args: str) -> dict:
    from .. import db
    from ..agents.permissions import is_permitted   # 延迟导入，避免 tools ↔ agents 循环依赖
    ok, reason = is_permitted(ctx.bot, name, ctx.depth)
    if not ok:
        log.warning("tool denied: user=%s bot=%s tool=%s reason=%s", ctx.user_id, ctx.bot.get("id"), name, reason)
        db.audit(ctx.user_id, ctx.bot.get("id"), "tool_denied", {"tool": name, "reason": reason, "depth": ctx.depth})
        msg = {"unknown_tool": f"未知工具: {name}", "tool_not_allowed": "当前 Bot 未被授权使用该能力",
               "max_depth": "已达到最大委派深度，不能继续转交"}[reason]
        return {"error": msg, "code": reason}
    try:
        args = json.loads(raw_args or "{}")
        if not isinstance(args, dict):
            raise ValueError("arguments must be an object")
    except Exception as e:
        return {"error": f"参数解析失败: {e}"}
    try:
        return await REGISTRY[name].handler(ctx, **args)
    except TypeError as e:
        return {"error": f"参数不匹配: {e}"}
    except Exception as e:  # 工具异常不应打断对话
        log.exception("tool %s failed", name)
        return {"error": f"工具执行失败: {type(e).__name__}: {e}"}
