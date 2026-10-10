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
    memory_proposals: int = 0     # 本轮记忆提议次数（remember / forget_memory），上限 VERABOT_MEMORY_PROPOSALS_PER_TURN
    mcp_calls: int = 0            # 本轮已经打到 MCP 服务器的次数（含只读；待确认不计入）
    pending_created: int = 0      # 本轮创建的待确认操作数，上限 VERABOT_MCP_PENDING_PER_TURN
    mcp_read_servers: set = field(default_factory=set)  # 本轮读过的 MCP 服务显示名（跨服务警告）
    untrusted_tainted: bool = False  # 本轮已经读过 MCP 结果，不能再 ask_bot
    reminder_writes: int = 0      # 本轮提醒写操作次数，上限 5
    reminder_created: dict = field(default_factory=dict)  # (标题, due_utc) → 已创建结果，同一轮去重
    # SSE status 事件（委派内部进度）：外层工具执行期间由 run_chat 设置；None = 不推送（如测试直接调用 run_tool）
    status_queue: Any = None
    parent_id: str | None = None  # 外层（depth 0）工具调用 id，委派树内所有 status 事件都带它
    # 图片附件（v12）：本轮模型看到的图片 id（新图 + 召回，委派时原样转给被委派 Bot）；
    # image_tainted = 本轮含图片，写工具需要用户确认；pending_images = view_image 待附上的原图
    image_ids: list = field(default_factory=list)
    image_tainted: bool = False
    recalls: int = 0
    pending_images: list = field(default_factory=list)
    file_ids: list = field(default_factory=list)
    file_reads: int = 0
    file_owner_bot_id: int | None = None


@dataclass
class ToolContext:
    user_id: int
    bot: dict                      # 当前执行工具的 Bot（含 allowed_tools / delegate_to / accept_delegation）
    depth: int = 0                 # 多 Agent 调用深度：0 = 用户直接对话的 Bot
    chain: list = field(default_factory=list)      # 委派链上的 Bot id（用于环路检测 Loop detection）
    turn: TurnState = field(default_factory=TurnState)
    usage: list = field(default_factory=list)      # 子调用产生的 token 用量
    user_message_id: int | None = None             # 本轮用户消息 id（记忆提议的来源 source_message_id）
    user_text: str = ""                             # 本轮原始用户文本；供明确相对时间等规则校验使用


@dataclass
class Tool:
    name: str
    description: str
    parameters: dict
    handler: Callable[..., Awaitable[Any]]
    delegation: bool = False       # 是否为委派类工具（受 MAX_DELEGATION_DEPTH 约束）
    kind: str = "builtin"          # builtin / memory / attachment。memory 类工具不进 allowed_tools，由 bots.memory_access 控制；
                                   # attachment（view_image）只在对话含图时由 runtime 暴露，不进 allowed_tools，被委派时禁止

    def schema(self) -> dict:
        return {"type": "function",
                "function": {"name": self.name, "description": self.description, "parameters": self.parameters}}


REGISTRY: dict[str, Tool] = {}


def tool(name: str, description: str, parameters: dict, delegation: bool = False, kind: str = "builtin"):
    def deco(fn):
        if name.startswith("mcp__"):
            raise RuntimeError(f"内置工具名不能以 mcp__ 开头: {name}")
        REGISTRY[name] = Tool(name, description, parameters, fn, delegation, kind)
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
               "max_depth": "已达到最大委派深度，不能继续转交",
               "memory_not_delegable": "被委派时不能读写用户记忆", "memory_disabled": "这个 Bot 未开启记忆",
               "reminder_not_delegable": "被委派时不能读写提醒"}[reason]
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
