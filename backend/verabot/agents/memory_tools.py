"""记忆工具（Memory tools）：remember / forget_memory。只生成「待确认」提议，真正生效要用户在确认卡片上点「记住」。

注册方式与 ask_bot 相同（tools/__init__ 导入即注册，kind="memory"）。权限：permissions.is_permitted 按
bots.memory_access + depth 判定（被委派时禁止）；业务规则全部在 services.memory.propose。
"""
from ..services import memory
from ..tools.registry import ToolContext, tool


@tool("remember",
      "提议把一条关于用户的长期信息记下来。用于：用户明确要求记住，或用户说出明显长期有效的个人资料 / 偏好。"
      "调用后系统会向用户显示确认卡片，用户确认前不会保存。不要用于一次性信息、他人隐私、密码 / 验证码 / 证件号 / 卡号。"
      "如果是修改已有记忆，传 replaces_memory_id（取自 <user_memory> 中的 M 编号）。",
      {"type": "object", "properties": {
          "content": {"type": "string", "description": "用第三人称、一句话陈述，如「用户不吃香菜」，最多 200 字"},
          "type": {"type": "string", "enum": ["profile", "preference", "fact"],
                   "description": "profile = 基本资料；preference = 偏好；fact = 与你的职责相关的事实"},
          "scope": {"type": "string", "enum": ["global", "bot"],
                    "description": "global = 所有 Bot 都适用的个人资料 / 偏好；bot = 只与你的职责相关"},
          "replaces_memory_id": {"type": "integer", "description": "可选：要更新的记忆编号"}},
       "required": ["content", "type", "scope"]},
      kind="memory")
async def remember(ctx: ToolContext, content: str, type: str = "fact", scope: str = "global",
                   replaces_memory_id: int | None = None):
    return memory.propose(ctx.user_id, ctx.bot, ctx.turn, action="create", content=content, type=type, scope=scope,
                          target_id=replaces_memory_id, user_message_id=ctx.user_message_id)


@tool("forget_memory", "用户要求忘掉某条记忆时调用，传 <user_memory> 中的 M 编号。系统会请用户确认后删除。",
      {"type": "object", "properties": {"memory_id": {"type": "integer", "description": "要忘掉的记忆编号"}},
       "required": ["memory_id"]},
      kind="memory")
async def forget_memory(ctx: ToolContext, memory_id: int):
    return memory.propose(ctx.user_id, ctx.bot, ctx.turn, action="delete", target_id=memory_id,
                          user_message_id=ctx.user_message_id)
